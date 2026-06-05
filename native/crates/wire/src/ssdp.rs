//! Own multi-interface SSDP. sonos-sdk's discovery bound 0.0.0.0 and
//! failed on multi-NIC hosts (spike findings / tatimblin/sonos-sdk#76),
//! which is why oto-wire runs its own SSDP — we enumerate interfaces,
//! bind each explicitly, AND pin each socket's outgoing multicast
//! interface (`IP_MULTICAST_IF` via `set_multicast_if_v4`). Binding to a
//! NIC's unicast address alone does NOT select the egress interface for a
//! multicast datagram — the OS picks that from its multicast routing
//! table (typically one default NIC), so without the pin every per-NIC
//! M-SEARCH can leave the same adapter and speakers reachable only via
//! another NIC never hear the query. The `examples/ssdp_multicast_if_probe`
//! A/B diagnostic demonstrates this on a real multi-NIC LAN.
//!
//! Discovery is two-phase: first send an M-SEARCH on *every* usable
//! interface, then receive across *all* of them inside a single bounded
//! deadline. Phase-2 multiplexing is done with `mio::Poll` so the wait is
//! **collective** — a quiet socket cannot consume any of the deadline,
//! no matter how many quiet sockets sit between us and a responder. The
//! previous design used per-socket blocking reads with a 250 ms read
//! timeout, so a host that enumerated 13+ quiet adapters before the
//! responding one (multi-NIC Windows hosts with VPN/Hyper-V/WSL/Docker
//! adapters) could burn the entire bounded window on timeouts and never
//! reach the responder.

use std::collections::BTreeSet;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::time::{Duration, Instant};

use mio::net::UdpSocket;
use mio::{Events, Interest, Poll, Token};
use socket2::{Domain, Protocol, Socket, Type};

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
/// IPv4-only by design; IPv6 SSDP (`FF02::C`) is out of scope today.
/// IPv4-only; IPv6 SSDP is out of scope.
///
/// `if_addrs::get_if_addrs()` returns `io::Result<Vec<Interface>>`; each
/// `Interface` exposes `.ip() -> IpAddr`, `.is_loopback()`, and
/// `.is_link_local()` directly (verified against `if-addrs` 0.15 source).
fn usable_ipv4() -> Result<Vec<Ipv4Addr>, WireError> {
    let ifaces = if_addrs::get_if_addrs()
        .map_err(|e| WireError::Network(format!("if_addrs::get_if_addrs: {e}")))?;
    let addrs = ifaces
        .into_iter()
        .filter(|i| !i.is_loopback() && !i.is_link_local())
        .filter_map(|i| match i.ip() {
            IpAddr::V4(v4) => Some(v4),
            IpAddr::V6(_) => None,
        })
        .collect();
    Ok(addrs)
}

/// Build one non-blocking IPv4 UDP socket bound to `ip:0` with its
/// outgoing multicast interface pinned to `ip` (`IP_MULTICAST_IF`).
///
/// Pinning the egress interface is the actual multi-NIC fix
/// ([`tatimblin/sonos-sdk#76`]): binding to a NIC's unicast address does
/// NOT, on its own, decide which interface a multicast datagram leaves by
/// — the OS chooses that from its multicast routing table (usually one
/// default NIC). Without the pin, every per-NIC M-SEARCH can egress the
/// same adapter and a speaker reachable only via a different NIC is never
/// queried. `std::net` exposes no setter for this, hence `socket2`.
///
/// [`tatimblin/sonos-sdk#76`]: https://github.com/tatimblin/sonos-sdk/issues/76
fn bind_multicast_sender(ip: Ipv4Addr) -> std::io::Result<UdpSocket> {
    let sock = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    sock.set_nonblocking(true)?;
    sock.set_multicast_if_v4(&ip)?;
    sock.bind(&SocketAddr::new(IpAddr::V4(ip), 0).into())?;
    // socket2::Socket → std::net::UdpSocket → mio::net::UdpSocket. The
    // socket is already non-blocking, which `from_std` requires.
    Ok(UdpSocket::from_std(sock.into()))
}

/// Receive SSDP replies across ALL sockets until `deadline`, collecting
/// unique LOCATION URLs.
///
/// Uses `mio::Poll` so the wait is **collective**: one `poll()` call
/// blocks until any socket is readable or the remaining-time budget
/// elapses. There is no per-socket timeout to consume, so a host with
/// many quiet adapters cannot starve a responder bound to a later
/// socket. Each ready socket is drained to `WouldBlock` so a burst of
/// replies on one interface doesn't require another `poll()` round-trip.
fn collect_until(poll: &mut Poll, sockets: &[UdpSocket], deadline: Instant) -> BTreeSet<String> {
    let mut found = BTreeSet::new();
    // Capacity tracks socket count so a single `poll` call can surface
    // every ready socket without growing the buffer mid-loop. `.max(8)`
    // keeps the allocation reasonable for single-NIC hosts.
    let mut events = Events::with_capacity(sockets.len().max(8));
    let mut buf = [0u8; 2048];
    while let Some(remaining) = deadline.checked_duration_since(Instant::now()) {
        // EINTR is benign on platforms where mio doesn't already swallow it
        // (some BSDs / older platforms) — retry within the bounded window.
        // Any other error means the poller itself is wedged (e.g. EBADF
        // after a registration we no longer own); retrying would
        // tight-spin until the deadline and silently mask the failure.
        // Stop the wait loop and return what we have already collected;
        // discover() will surface NoDevicesFound if `found` is empty,
        // and the next discover_with() call constructs a fresh Poll.
        match poll.poll(&mut events, Some(remaining)) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        }
        for event in events.iter() {
            if !event.is_readable() {
                continue;
            }
            let idx = event.token().0;
            // Drain everything available on this socket. Repeats are
            // cheap and avoid relying on level-vs-edge triggering
            // semantics. A hard error (e.g. Windows WSAECONNRESET from
            // an ICMP port-unreachable to the M-SEARCH) ends the drain
            // for this socket only; other sockets keep working.
            loop {
                match sockets[idx].recv_from(&mut buf) {
                    Ok((n, _)) => {
                        // TODO(v0.6): accepted-risk hardening. We take any
                        // datagram carrying a LOCATION header — we do NOT
                        // validate the SSDP status line or `ST`, match the
                        // LOCATION host against the responder's source
                        // address (discarded as `_` here), or cap the
                        // candidate count. A hostile device already on the
                        // user's LAN could therefore inject a LOCATION that
                        // points discovery's follow-up GetZoneGroupState
                        // SOAP at an arbitrary host (port 1400 only — the
                        // LOCATION port is ignored downstream). Accepted for
                        // v0.5: LAN-local threat, blast radius is junk SOAP
                        // attempts (a non-Sonos host fails to parse and is
                        // skipped), and `discover()` stops at the first
                        // responder that returns a parseable topology.
                        // Harden in v0.6 (validate 200 + `ST`, require the
                        // LOCATION host == source IP, cap candidates) —
                        // wants a hardware re-validation pass on the LAN.
                        if let Some(loc) = location_of(&String::from_utf8_lossy(&buf[..n])) {
                            found.insert(loc);
                        }
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                    Err(_) => break,
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
/// - **Phase 1 (send-all, non-blocking):** bind one non-blocking UDP
///   socket per usable interface with its multicast egress interface
///   pinned to that NIC (see `bind_multicast_sender`), register it with
///   the shared `Poll`, and send a ZonePlayer M-SEARCH on each. Interfaces
///   that cannot be set up or cannot egress multicast are skipped; only
///   the case where *every* interface fails is fatal — surfaced as
///   `WireError::Network` with the last underlying cause so a local
///   stack/socket failure is not misreported as `NoDevicesFound`.
/// - **Phase 2 (recv-all, collective):** wait on all sockets via
///   `mio::Poll` until the deadline. Every readable socket is drained on
///   each wakeup, so a quiet socket cannot consume the wait budget.
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
    let ssdp_target: SocketAddr = SSDP_ADDR
        .parse()
        .expect("SSDP_ADDR is a valid literal SocketAddr");
    let deadline = Instant::now() + timeout;

    let mut poll = Poll::new().map_err(|e| WireError::Network(format!("mio::Poll::new: {e}")))?;
    let mut sockets: Vec<UdpSocket> = Vec::new();
    // Distinct from the "no usable IPv4 interface" branch: we DID find
    // interfaces, but each individual bind/send/register may fail (e.g. a
    // virtual adapter with no route to 239.x). Per-interface failure is
    // non-fatal — we want to try the rest. We retain the last underlying
    // error so the all-failed case surfaces it (rather than the caller
    // mapping `Ok(vec![])` to `NoDevicesFound`, which falsely implies the
    // LAN is empty).
    let mut last_err: Option<String> = None;

    // Phase 1 — bind + register + send on ALL usable interfaces.
    for ip in ifaces {
        let mut sock = match bind_multicast_sender(ip) {
            Ok(s) => s,
            Err(e) => {
                last_err = Some(format!("socket {ip}: {e}"));
                continue;
            }
        };
        if let Err(e) = sock.send_to(msearch.as_bytes(), ssdp_target) {
            // Interface can't egress multicast (e.g. a virtual adapter with no
            // route to 239.x). Skip it and try the remaining interfaces.
            last_err = Some(format!("send_to {ip}: {e}"));
            continue;
        }
        let token = Token(sockets.len());
        if let Err(e) = poll
            .registry()
            .register(&mut sock, token, Interest::READABLE)
        {
            last_err = Some(format!("register {ip}: {e}"));
            continue;
        }
        sockets.push(sock);
    }
    if sockets.is_empty() {
        // Every usable interface failed bind/send/register. Surface the
        // precise cause so the caller does not report an empty LAN.
        let detail = last_err.unwrap_or_else(|| "all interfaces failed bind/send".into());
        return Err(WireError::Network(format!(
            "SSDP failed on every usable interface: {detail}"
        )));
    }

    // Phase 2 — receive across ALL sockets until the single deadline.
    let found = collect_until(&mut poll, &sockets, deadline);
    Ok(found.into_iter().collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::UdpSocket as StdUdpSocket;

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

    /// Bind a non-blocking UDP socket on localhost and register it with
    /// `poll` under the supplied token index. Returns the mio socket plus
    /// its local address (so a sender can target it).
    fn bind_and_register(poll: &mut Poll, idx: usize) -> (UdpSocket, SocketAddr) {
        let mut sock = UdpSocket::bind("127.0.0.1:0".parse().expect("literal")).expect("mio bind");
        let addr = sock.local_addr().expect("local_addr");
        poll.registry()
            .register(&mut sock, Token(idx), Interest::READABLE)
            .expect("register");
        (sock, addr)
    }

    /// Regression guard for the v0.1 [P1] multi-NIC discovery bug: with
    /// the prior design the recv loop blocked on the first socket until
    /// the global deadline, so a second interface's reply was never read.
    /// `collect_until` must surface replies from *both* sockets.
    ///
    /// Localhost only (127.0.0.1) — NOT the Sonos LAN, so allowed in
    /// sandbox/CI per AGENTS.md §5. The mio recv path returns the
    /// moment either socket has data; the only real latency is the
    /// sender's 50 ms inter-send delay. The test's deadline is its
    /// effective wall-time cap — 400 ms comfortably covers 50 ms of
    /// delay plus scheduler jitter while staying well under the 1 s gate.
    #[test]
    fn collect_until_round_robins_across_all_sockets() {
        use std::thread;

        let mut poll = Poll::new().expect("poll");
        let (sock_a, addr_a) = bind_and_register(&mut poll, 0);
        let (sock_b, addr_b) = bind_and_register(&mut poll, 1);

        let sender = thread::spawn(move || {
            let tx = StdUdpSocket::bind("127.0.0.1:0").expect("bind sender");
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
            &mut poll,
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
    /// not push `collect_until` meaningfully past its deadline. With the
    /// mio path the wait is collective — `poll()` returns the moment the
    /// deadline elapses with no work to do, so the overshoot is bounded
    /// by scheduler granularity rather than any per-socket timeout.
    #[test]
    fn collect_until_does_not_overshoot_deadline() {
        let mut poll = Poll::new().expect("poll");
        let (sock, _addr) = bind_and_register(&mut poll, 0);

        let start = Instant::now();
        let found = collect_until(&mut poll, &[sock], start + Duration::from_millis(300));
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

    /// Regression for the per-socket-timeout starvation bug: with the
    /// prior stdlib design and 13 quiet sockets ahead of the responder,
    /// Phase 1 of `collect_until` blocked 250 ms per quiet socket. After
    /// 12 quiet timeouts the loop's per-iteration deadline guard tripped
    /// and the responder was never read, even though it had sent its
    /// reply well within the bounded window.
    ///
    /// With `mio::Poll` the wait is collective: one `poll()` call wakes
    /// up the moment the responder is readable, regardless of how many
    /// quiet sockets share the same `Poll`. 13 quiet sockets is past the
    /// old bug's threshold for a 3 s outer window with a 250 ms inner
    /// timeout. The test uses a 600 ms deadline so a regression to the
    /// old design (which would block for at least 13 × 250 ms = 3.25 s
    /// before reaching the responder) would actually time out the
    /// assertion. Localhost only — allowed in sandbox/CI per AGENTS.md §5.
    #[test]
    fn collect_until_handles_many_quiet_sockets() {
        use std::thread;

        let mut poll = Poll::new().expect("poll");
        let mut sockets: Vec<UdpSocket> = Vec::new();
        for _ in 0..13 {
            let (s, _addr) = bind_and_register(&mut poll, sockets.len());
            sockets.push(s);
        }
        let (responder, responder_addr) = bind_and_register(&mut poll, sockets.len());
        sockets.push(responder);

        let sender = thread::spawn(move || {
            let tx = StdUdpSocket::bind("127.0.0.1:0").expect("bind sender");
            let reply = "HTTP/1.1 200 OK\r\nLOCATION: http://10.99.99.99:1400/desc.xml\r\n\r\n";
            // Small delay so the recv loop is parked in `poll` when the
            // reply arrives, exercising the wakeup path.
            thread::sleep(Duration::from_millis(50));
            tx.send_to(reply.as_bytes(), responder_addr)
                .expect("send responder");
        });

        let found = collect_until(
            &mut poll,
            &sockets,
            Instant::now() + Duration::from_millis(600),
        );
        sender.join().expect("join sender thread");

        assert!(
            found.contains("http://10.99.99.99:1400/desc.xml"),
            "responder behind 13 quiet sockets was not received within the deadline; \
             a regression to the per-socket-timeout design would block long enough \
             to miss it. found={found:?}"
        );
    }
}
