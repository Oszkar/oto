//! Own multi-interface SSDP. sonos-sdk's discovery binds 0.0.0.0 and
//! fails on multi-NIC hosts (spike findings / tatimblin/sonos-sdk#76);
//! we enumerate interfaces and bind each explicitly.
//!
//! Discovery is two-phase: first send an M-SEARCH on *every* usable
//! interface, then receive across *all* of them (round-robin) until a
//! single bounded deadline. Every NIC is searched within one O(timeout)
//! window — no interface is starved by another, and no per-interface
//! sequential blocking (which on a host that enumerates a WSL/Hyper-V/VPN
//! vEthernet first would defeat multi-NIC discovery entirely).

use std::collections::BTreeSet;
use std::net::{IpAddr, UdpSocket};
use std::time::{Duration, Instant};

use oto_core::WireError;

const SSDP_ADDR: &str = "239.255.255.250:1900";
const ST: &str = "urn:schemas-upnp-org:device:ZonePlayer:1";

fn msearch() -> String {
    format!(
        "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n\
         MAN: \"ssdp:discover\"\r\nMX: 2\r\nST: {ST}\r\n\
         USER-AGENT: oto/0.1 UPnP/1.0\r\n\r\n"
    )
}

/// Extract the `LOCATION` value from one SSDP response payload.
fn location_of(payload: &str) -> Option<String> {
    payload
        .lines()
        .find(|l| l.to_ascii_lowercase().starts_with("location:"))
        .map(|l| l["location:".len()..].trim().to_string())
}

/// Usable IPv4 interface addresses (no loopback, no link-local).
///
/// `if_addrs::get_if_addrs()` returns `io::Result<Vec<Interface>>`; each
/// `Interface` exposes `.ip() -> IpAddr`, `.is_loopback()`, and
/// `.is_link_local()` directly (verified against `if-addrs` 0.15 source).
fn usable_ipv4() -> Result<Vec<IpAddr>, WireError> {
    let ifaces = if_addrs::get_if_addrs()
        .map_err(|e| WireError::Network(format!("if_addrs::get_if_addrs: {e}")))?;
    let addrs = ifaces
        .into_iter()
        .filter(|i| !i.is_loopback() && !i.is_link_local())
        .filter_map(|i| match i.ip() {
            addr @ IpAddr::V4(_) => Some(addr),
            IpAddr::V6(_) => None,
        })
        .collect();
    Ok(addrs)
}

/// Receive SSDP replies across ALL sockets until `deadline`, collecting
/// unique LOCATION URLs. Round-robins so a quiet socket never starves the
/// others and no single socket can consume the whole window (the v0.1
/// multi-NIC discovery bug). Each socket must already have a short
/// read timeout set.
fn collect_until(socks: &[UdpSocket], deadline: Instant) -> BTreeSet<String> {
    let mut found = BTreeSet::new();
    let mut buf = [0u8; 2048];
    // Round-robin across ALL sockets so a quiet socket never starves the
    // others (the v0.1 [P1] multi-NIC bug). The deadline is re-checked
    // *before each socket* (not once per full pass) and the hard-error
    // sleep below is clamped to the remaining window, so total wall time is
    // strictly O(timeout): bounded by at most one socket's read-timeout
    // granularity (~250 ms) past `deadline`, independent of socket count.
    // TODO(v0.2): per-socket consecutive-error budget instead of a blanket
    // sleep (e.g. drop a socket after N hard errors) — lower priority now
    // that both busy-spin and overshoot are bounded.
    while Instant::now() < deadline {
        for sock in socks {
            // Stop mid-pass the instant the window closes so an in-progress
            // pass can't overshoot by N_sockets × the hard-error sleep; the
            // outer `while` then exits too.
            if Instant::now() >= deadline {
                break;
            }
            match sock.recv_from(&mut buf) {
                Ok((n, _)) => {
                    if let Some(loc) = location_of(&String::from_utf8_lossy(&buf[..n])) {
                        found.insert(loc);
                    }
                }
                Err(e)
                    if e.kind() == std::io::ErrorKind::WouldBlock
                        || e.kind() == std::io::ErrorKind::TimedOut => {}
                Err(_) => {
                    // A hard error (e.g. Windows WSAECONNRESET from an ICMP
                    // port-unreachable to the M-SEARCH) returns immediately. With a
                    // single socket (common single-NIC host) that would tight-spin
                    // until the deadline — pace it like a timed-out read. Never
                    // abort: other sockets/passes must keep working. Clamp the
                    // pacing sleep to the time left so it can never push wall
                    // time past `deadline` (saturating: ZERO if already past).
                    let remaining = deadline.saturating_duration_since(Instant::now());
                    if !remaining.is_zero() {
                        std::thread::sleep(remaining.min(Duration::from_millis(250)));
                    }
                    // If no time remains, don't sleep — the top-of-loop guard
                    // exits the pass on the next iteration.
                }
            }
        }
    }
    found
}

/// SSDP across every usable IPv4 interface. Returns unique LOCATION URLs.
///
/// Two-phase, so that **every** usable NIC is actually searched within a
/// single bounded window (the prior per-interface sequential design blocked
/// the recv loop on the first bindable+sendable socket until the global
/// deadline, so interfaces #2..N were never searched — defeating multi-NIC
/// discovery on a host that enumerates a WSL/Hyper-V/VPN vEthernet first):
///
/// - **Phase 1 (send-all, non-blocking):** bind one UDP socket per usable
///   interface and send a ZonePlayer M-SEARCH on each. Interfaces that
///   cannot be bound or cannot egress multicast are skipped; only the
///   `set_read_timeout` system call is fatal (a local OS error, not a
///   network condition).
/// - **Phase 2 (recv-all, round-robin):** receive across *all* sent sockets
///   until the deadline, so no single socket can consume the whole window.
///
/// `timeout` is the **total bounded window** across all interfaces: the
/// deadline is computed once up front, so wall time stays O(timeout)
/// regardless of NIC count (important on multi-NIC Windows hosts with
/// Docker/WSL/VPN adapters).
pub fn discover_locations(timeout: Duration) -> Result<Vec<String>, WireError> {
    let ifaces = usable_ipv4()?;
    if ifaces.is_empty() {
        return Err(WireError::Network("no usable IPv4 interface".into()));
    }
    let msearch = msearch();
    let deadline = Instant::now() + timeout;

    // Phase 1 — send on ALL usable interfaces (fast, non-blocking).
    let mut socks: Vec<UdpSocket> = Vec::new();
    for ip in ifaces {
        let sock = match UdpSocket::bind((ip, 0)) {
            Ok(s) => s,
            Err(_) => continue, // adapter unbindable (e.g. some VPN/tunnel) — skip, like send_to failure
        };
        // Short read timeout so the Phase-2 round-robin doesn't let one
        // quiet socket starve the pass; total time is still bounded by
        // `deadline`. The set_read_timeout syscall failing is a local OS
        // error, not a network condition — keep it fatal.
        sock.set_read_timeout(Some(Duration::from_millis(250)))
            .map_err(|e| WireError::Network(e.to_string()))?;
        if sock.send_to(msearch.as_bytes(), SSDP_ADDR).is_err() {
            // Interface can't egress multicast (e.g. a virtual adapter with no
            // route to 239.x); skip it and try remaining interfaces.
            continue;
        }
        socks.push(sock);
    }
    if socks.is_empty() {
        // All interfaces failed bind/send; caller sees location_count == 0
        // and maps that to NoDevicesFound — no need to distinguish here.
        return Ok(Vec::new());
    }

    // Phase 2 — receive across ALL sockets until the single deadline.
    let found = collect_until(&socks, deadline);
    Ok(found.into_iter().collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_location_case_insensitive() {
        let resp = "HTTP/1.1 200 OK\r\n\
                    LOCATION: http://10.83.0.10:1400/xml/device_description.xml\r\n\
                    ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n";
        assert_eq!(
            location_of(resp).as_deref(),
            Some("http://10.83.0.10:1400/xml/device_description.xml")
        );
    }

    #[test]
    fn parses_location_lowercase_header() {
        let resp = "HTTP/1.1 200 OK\r\n\
                    location: http://192.168.1.5:1400/xml/device_description.xml\r\n\
                    ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n";
        assert_eq!(
            location_of(resp).as_deref(),
            Some("http://192.168.1.5:1400/xml/device_description.xml")
        );
    }

    #[test]
    fn no_location_header_returns_none() {
        assert_eq!(
            location_of("HTTP/1.1 200 OK\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n"),
            None
        );
    }

    #[test]
    fn location_value_is_trimmed() {
        // Some devices emit trailing whitespace after the URL.
        let resp = "HTTP/1.1 200 OK\r\nLOCATION:  http://10.0.0.1:1400/desc.xml  \r\n\r\n";
        assert_eq!(
            location_of(resp).as_deref(),
            Some("http://10.0.0.1:1400/desc.xml")
        );
    }

    /// Regression guard for the v0.1 [P1] multi-NIC discovery bug: the old
    /// design recv'd on the first socket until the global deadline, so a
    /// second interface's reply was never read. `collect_until` must
    /// round-robin and surface replies from *both* sockets.
    ///
    /// Localhost only (127.0.0.1) — NOT the Sonos LAN, so allowed in
    /// sandbox/CI per AGENTS.md §5. Deterministic and fast: localhost
    /// datagram delivery is sub-millisecond, so the only real latency is
    /// the sender's 50ms inter-send delay. `collect_until` has no early
    /// exit by design (it keeps listening for slow real devices until the
    /// deadline), so the test's deadline IS its wall time — a 400ms upper
    /// bound comfortably covers the 50ms delay + 100ms read-timeout
    /// granularity with wide margin while staying well under the 1s gate.
    /// The sender thread is joined and both sockets have read timeouts, so
    /// the test never hangs.
    #[test]
    fn collect_until_round_robins_across_all_sockets() {
        use std::net::SocketAddr;
        use std::thread;

        let sock_a = UdpSocket::bind("127.0.0.1:0").expect("bind A");
        let sock_b = UdpSocket::bind("127.0.0.1:0").expect("bind B");
        sock_a
            .set_read_timeout(Some(Duration::from_millis(100)))
            .expect("set_read_timeout A");
        sock_b
            .set_read_timeout(Some(Duration::from_millis(100)))
            .expect("set_read_timeout B");
        let addr_a: SocketAddr = sock_a.local_addr().expect("local_addr A");
        let addr_b: SocketAddr = sock_b.local_addr().expect("local_addr B");

        let sender = thread::spawn(move || {
            let tx = UdpSocket::bind("127.0.0.1:0").expect("bind sender");
            let reply_a = "HTTP/1.1 200 OK\r\nLOCATION: http://10.0.0.1:1400/a.xml\r\n\r\n";
            let reply_b = "HTTP/1.1 200 OK\r\nLOCATION: http://10.0.0.2:1400/b.xml\r\n\r\n";
            tx.send_to(reply_a.as_bytes(), addr_a).expect("send A");
            // Slight delay before B's reply makes the "stuck on first
            // socket" failure mode observable while staying deterministic
            // and well inside the deadline.
            thread::sleep(Duration::from_millis(50));
            tx.send_to(reply_b.as_bytes(), addr_b).expect("send B");
        });

        let found = collect_until(
            &[sock_a, sock_b],
            Instant::now() + Duration::from_millis(400),
        );
        sender.join().expect("join sender thread");

        assert!(
            found.contains("http://10.0.0.1:1400/a.xml"),
            "missing socket A's LOCATION; found={found:?}"
        );
        assert!(
            found.contains("http://10.0.0.2:1400/b.xml"),
            "missing socket B's LOCATION (the [P1] failure mode: \
             stuck on the first socket); found={found:?}"
        );
    }

    /// Regression guard for the "wall time stays O(timeout)" contract: a
    /// socket that only ever times out (nothing is ever sent to it) must
    /// not push `collect_until` meaningfully past its deadline. Bounds the
    /// overshoot to ~one read-timeout granularity regardless of error
    /// regime (the top-of-loop deadline guard + clamped pacing sleep).
    ///
    /// Localhost only, deterministic, no sender thread: relies purely on
    /// the socket's own 100ms read timeout pacing the recv loop, so there
    /// is no scheduling race. Deadline 300ms; the 600ms wall bound leaves
    /// wide slack for one read-timeout granularity + scheduler jitter while
    /// staying well under the 1s gate. Returns the empty set (nothing sent).
    #[test]
    fn collect_until_does_not_overshoot_deadline() {
        let sock = UdpSocket::bind("127.0.0.1:0").expect("bind");
        sock.set_read_timeout(Some(Duration::from_millis(100)))
            .expect("set_read_timeout");

        let start = Instant::now();
        let found = collect_until(&[sock], start + Duration::from_millis(300));
        let elapsed = start.elapsed();

        assert!(
            found.is_empty(),
            "nothing was sent; expected empty set, found={found:?}"
        );
        assert!(
            elapsed < Duration::from_millis(600),
            "collect_until overshot its 300ms deadline: took {elapsed:?} \
             (must stay O(timeout), not N×sleep)"
        );
    }
}
