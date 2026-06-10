//! Hardware spike for the v0.5 SSDP multicast-egress fix
//! ([`tatimblin/sonos-sdk#76`]). Run by hand on the multi-NIC LAN.
//!
//! For every usable IPv4 NIC it sends the ZonePlayer M-SEARCH twice and
//! counts the distinct SSDP responders each socket hears back:
//!   - **no-pin:** bound to the NIC, but WITHOUT `IP_MULTICAST_IF` — this
//!     is the pre-fix production behavior (the OS picks the egress NIC).
//!   - **pin-egress:** bound to the NIC AND `set_multicast_if_v4(nic)` —
//!     the fix now in `ssdp.rs::bind_multicast_sender`.
//!
//! If any NIC reaches more responders under `pin-egress`, the M-SEARCH was
//! leaving the wrong interface without the pin — #76 confirmed on this
//! host. On a host where the Sonos household sits on the OS default
//! multicast interface, both columns match (the fix is still correct; the
//! bug just isn't triggered in that topology).
//!
//! ```text
//! cargo run -p oto-wire --example ssdp_multicast_if_probe
//! ```
//!
//! Diagnostic only — NOT part of the product surface.
//!
//! [`tatimblin/sonos-sdk#76`]: https://github.com/tatimblin/sonos-sdk/issues/76

use std::collections::BTreeSet;
use std::net::{IpAddr, Ipv4Addr, SocketAddr, UdpSocket};
use std::time::{Duration, Instant};

use socket2::{Domain, Protocol, Socket, Type};

const SSDP_TARGET: &str = "239.255.255.250:1900";
const MSEARCH: &str = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n\
     MAN: \"ssdp:discover\"\r\nMX: 2\r\n\
     ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\
     USER-AGENT: oto-spike/0.5 UPnP/1.0\r\n\r\n";

fn usable_ipv4() -> Vec<Ipv4Addr> {
    if_addrs::get_if_addrs()
        .unwrap_or_default()
        .into_iter()
        .filter(|i| !i.is_loopback() && !i.is_link_local())
        .filter_map(|i| match i.ip() {
            IpAddr::V4(v4) => Some(v4),
            IpAddr::V6(_) => None,
        })
        .collect()
}

/// Non-blocking IPv4 UDP socket bound to `ip:0`. When `pin_egress`, also
/// pin the outgoing multicast interface to `ip` — mirroring the two
/// behaviors the probe compares.
fn sender(ip: Ipv4Addr, pin_egress: bool) -> std::io::Result<UdpSocket> {
    let sock = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    sock.set_nonblocking(true)?;
    if pin_egress {
        sock.set_multicast_if_v4(&ip)?;
    }
    sock.bind(&SocketAddr::new(IpAddr::V4(ip), 0).into())?;
    Ok(sock.into())
}

fn is_ssdp_reply(payload: &[u8]) -> bool {
    let text = String::from_utf8_lossy(payload).to_ascii_lowercase();
    text.contains("location:") || text.contains("zoneplayer")
}

fn main() {
    let target: SocketAddr = SSDP_TARGET.parse().expect("literal SSDP target");
    let nics = usable_ipv4();
    if nics.is_empty() {
        eprintln!("no usable IPv4 NIC — nothing to probe");
        std::process::exit(1);
    }
    println!(
        "== probing {} NIC(s); two M-SEARCH sends each (no-pin vs pin-egress) ==\n",
        nics.len()
    );

    // One probe per (NIC, mode). Distinct responder source IPs are deduped.
    struct Probe {
        ip: Ipv4Addr,
        pinned: bool,
        sock: UdpSocket,
        responders: BTreeSet<IpAddr>,
    }
    let mut probes: Vec<Probe> = Vec::new();
    for &ip in &nics {
        for pinned in [false, true] {
            match sender(ip, pinned) {
                Ok(sock) => match sock.send_to(MSEARCH.as_bytes(), target) {
                    Ok(_) => probes.push(Probe {
                        ip,
                        pinned,
                        sock,
                        responders: BTreeSet::new(),
                    }),
                    Err(e) => println!("  {ip} pin={pinned}: send_to failed: {e}"),
                },
                Err(e) => println!("  {ip} pin={pinned}: socket setup failed: {e}"),
            }
        }
    }

    // Collect for 4 s across all sockets without per-socket timeouts.
    let deadline = Instant::now() + Duration::from_secs(4);
    let mut buf = [0u8; 2048];
    while Instant::now() < deadline {
        let mut progressed = false;
        for probe in probes.iter_mut() {
            // A recv error is the steady state here: WouldBlock when idle,
            // or a per-socket hard error (e.g. Windows WSAECONNRESET from an
            // ICMP port-unreachable to our M-SEARCH) — both benign for a
            // diagnostic, so we ignore the Err arm and keep polling the rest.
            if let Ok((n, from)) = probe.sock.recv_from(&mut buf)
                && is_ssdp_reply(&buf[..n])
            {
                probe.responders.insert(from.ip());
                progressed = true;
            }
        }
        if !progressed {
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    println!("{:<18}{:>12}{:>14}", "NIC", "no-pin", "pin-egress");
    let mut fix_helped = false;
    for &ip in &nics {
        let count = |pinned: bool| {
            probes
                .iter()
                .find(|p| p.ip == ip && p.pinned == pinned)
                .map(|p| p.responders.len())
                .unwrap_or(0)
        };
        let no_pin = count(false);
        let pinned = count(true);
        let flag = if pinned > no_pin {
            fix_helped = true;
            "  <-- pin reaches more responders"
        } else {
            ""
        };
        println!("{:<18}{:>12}{:>14}{}", ip.to_string(), no_pin, pinned, flag);
    }

    println!();
    if fix_helped {
        println!(
            "RESULT: at least one NIC needed IP_MULTICAST_IF to reach Sonos — #76 \
             confirmed on this host; the ssdp.rs fix is load-bearing here."
        );
    } else {
        println!(
            "RESULT: both modes matched on every NIC — Sonos is reachable via the OS \
             default multicast interface on this host, so the bug isn't triggered \
             here. The fix is still correct (it makes egress deterministic per NIC)."
        );
    }
}
