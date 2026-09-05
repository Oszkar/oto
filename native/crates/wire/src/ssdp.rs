//! Own multi-interface SSDP. sonos-sdk's discovery bound 0.0.0.0 and
//! failed on multi-NIC hosts (spike findings / tatimblin/sonos-sdk#76),
//! which is why oto-wire runs its own SSDP - we enumerate interfaces,
//! bind each explicitly, AND pin each socket's outgoing multicast
//! interface (`IP_MULTICAST_IF` via `set_multicast_if_v4`). Binding to a
//! NIC's unicast address alone does NOT select the egress interface for a
//! multicast datagram - the OS picks that from its multicast routing
//! table (typically one default NIC), so without the pin every per-NIC
//! M-SEARCH can leave the same adapter and speakers reachable only via
//! another NIC never hear the query. The `examples/ssdp_multicast_if_probe`
//! A/B diagnostic demonstrates this on a real multi-NIC LAN.
//!
//! Discovery is two-phase: first send an M-SEARCH on *every* usable
//! interface, then receive across *all* of them inside a single bounded
//! deadline. Phase-2 multiplexing is done with `mio::Poll` so the wait is
//! **collective** - a quiet socket cannot consume any of the deadline,
//! no matter how many quiet sockets sit between us and a responder. The
//! previous design used per-socket blocking reads with a 250 ms read
//! timeout, so a host that enumerated 13+ quiet adapters before the
//! responding one (multi-NIC Windows hosts with VPN/Hyper-V/WSL/Docker
//! adapters) could burn the entire bounded window on timeouts and never
//! reach the responder.

use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::time::{Duration, Instant};

use mio::net::UdpSocket;
use mio::{Events, Interest, Poll, Token};
use socket2::{Domain, Protocol, Socket, Type};

use oto_core::WireError;

const SSDP_ADDR: &str = "239.255.255.250:1900";
const ST: &str = "urn:schemas-upnp-org:device:ZonePlayer:1";
// Bound memory independently of the number of advertisements or URL variants.
const MAX_CANDIDATE_HOSTS: usize = 32;
const RECEIVE_BATCH: usize = 32;

fn msearch() -> String {
    format!(
        "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n\
         MAN: \"ssdp:discover\"\r\nMX: 2\r\nST: {ST}\r\n\
         USER-AGENT: oto/0.1 UPnP/1.0\r\n\r\n"
    )
}

/// Accept only complete search replies advertising their sender's literal IP.
/// This is destination validation, not authentication of a LAN peer.
fn candidate_of(payload: &[u8], sender: SocketAddr) -> Option<Ipv4Addr> {
    let payload = std::str::from_utf8(payload).ok()?;
    let mut lines = payload.lines();
    let mut status = lines.next()?.split_ascii_whitespace();
    if status.next()? != "HTTP/1.1" || status.next()? != "200" {
        return None;
    }
    let mut location = None;
    let mut target = None;
    let mut complete = false;
    for line in lines {
        if line.is_empty() {
            complete = true;
            break;
        }
        let (name, value) = line.split_once(':')?;
        let slot = if name.eq_ignore_ascii_case("location") {
            &mut location
        } else if name.eq_ignore_ascii_case("st") {
            &mut target
        } else {
            continue;
        };
        if slot.replace(value.trim()).is_some() {
            return None;
        }
    }
    if !complete || target? != ST {
        return None;
    }
    let url = location?;
    if url
        .bytes()
        .any(|b| b.is_ascii_whitespace() || b.is_ascii_control())
    {
        return None;
    }
    let authority = url.strip_prefix("http://")?.split('/').next()?;
    let host = if let Some((host, port)) = authority.split_once(':') {
        if port.is_empty()
            || !port.bytes().all(|b| b.is_ascii_digit())
            || port.parse::<u16>().ok()? == 0
        {
            return None;
        }
        host
    } else {
        authority
    };
    let ip: Ipv4Addr = host.parse().ok()?;
    (IpAddr::V4(ip) == sender.ip()).then_some(ip)
}

fn admit_candidate(found: &mut Vec<Ipv4Addr>, ip: Ipv4Addr) {
    if found.len() < MAX_CANDIDATE_HOSTS && !found.contains(&ip) {
        found.push(ip);
    }
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
/// NOT, on its own, decide which interface a multicast datagram leaves by -
/// the OS chooses that from its multicast routing table (usually one
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

/// Collect first-seen unique hosts, rotating bounded batches across ready NICs.
/// Retain readiness until WouldBlock: mio need not emit another edge for an
/// incompletely drained socket. Poll without blocking between rounds so a new
/// sparse responder is noticed even while another socket stays continuously busy.
fn collect_until(
    poll: &mut Poll,
    sockets: &[UdpSocket],
    deadline: Instant,
) -> Result<Vec<Ipv4Addr>, WireError> {
    let mut found = Vec::new();
    let mut ready = vec![false; sockets.len()];
    let mut events = Events::with_capacity(sockets.len().max(8));
    // One extra byte lets us reject oversized/truncated datagrams on platforms
    // that return a truncated payload instead of an error.
    let mut buf = [0u8; 2049];
    while let Some(remaining) = deadline.checked_duration_since(Instant::now()) {
        let wait = if ready.contains(&true) {
            Duration::ZERO
        } else {
            remaining
        };
        match poll.poll(&mut events, Some(wait)) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) if found.is_empty() => {
                return Err(WireError::Network(format!("mio::Poll::poll: {e}")));
            }
            Err(_) => break,
        }
        for event in events.iter().filter(|event| event.is_readable()) {
            ready[event.token().0] = true;
        }
        for (idx, pending) in ready.iter_mut().enumerate() {
            if !*pending {
                continue;
            }
            for _ in 0..RECEIVE_BATCH {
                if Instant::now() >= deadline {
                    return Ok(found);
                }
                match sockets[idx].recv_from(&mut buf) {
                    Ok((n, sender)) => {
                        if n < buf.len()
                            && let Some(ip) = candidate_of(&buf[..n], sender)
                        {
                            admit_candidate(&mut found, ip);
                        }
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                    // Includes WouldBlock and per-socket failures (e.g.
                    // Windows ICMP port-unreachable); other NICs keep working.
                    Err(_) => {
                        *pending = false;
                        break;
                    }
                }
            }
        }
    }
    Ok(found)
}

/// SSDP across every usable IPv4 interface. Returns validated, unique IPv4 hosts in arrival order.
///
/// Two-phase, so that **every** usable NIC is actually searched within a
/// single bounded window (the prior per-interface sequential design blocked
/// the recv loop on the first bindable+sendable socket until the global
/// deadline, so interfaces #2..N were never searched - defeating multi-NIC
/// discovery on a host that enumerates a WSL/Hyper-V/VPN vEthernet first):
///
/// - **Phase 1 (send-all, non-blocking):** bind one non-blocking UDP
///   socket per usable interface with its multicast egress interface
///   pinned to that NIC (see `bind_multicast_sender`), register it with
///   the shared `Poll`, and send a ZonePlayer M-SEARCH on each. Interfaces
///   that cannot be set up or cannot egress multicast are skipped; only
///   the case where *every* interface fails is fatal - surfaced as
///   `WireError::Network` with the last underlying cause so a local
///   stack/socket failure is not misreported as `NoDevicesFound`.
/// - **Phase 2 (recv-all, collective):** wait on all sockets via
///   `mio::Poll` until the deadline. Ready sockets receive bounded turns, so busy or quiet sockets cannot
///   monopolize the receive window.
///
/// `timeout` sets one receive deadline, established before socket setup.
/// Interface enumeration and send-all setup are not interruptible; SOAP and
/// model enrichment happen afterward and are outside this receive budget.
pub fn discover_hosts(timeout: Duration) -> Result<Vec<Ipv4Addr>, WireError> {
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
    // non-fatal - we want to try the rest. We retain the last underlying
    // error so the all-failed case surfaces it (rather than the caller
    // mapping `Ok(vec![])` to `NoDevicesFound`, which falsely implies the
    // LAN is empty).
    let mut last_err: Option<String> = None;

    // Phase 1 - bind + register + send on ALL usable interfaces.
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

    // Phase 2 - receive across ALL sockets until the single deadline. A
    // poll() failure with nothing collected yet surfaces as
    // WireError::Network (see collect_until) rather than being conflated
    // with a genuinely empty LAN.
    let found = collect_until(&mut poll, &sockets, deadline)?;
    Ok(found)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::UdpSocket as StdUdpSocket;

    fn reply(ip: &str) -> String {
        format!("HTTP/1.1 200 OK\r\nLOCATION: http://{ip}:1400/desc.xml\r\nST: {ST}\r\n\r\n")
    }

    #[test]
    fn validates_search_reply() {
        let sender = "127.0.0.1:1900".parse().unwrap();
        let valid = reply("127.0.0.1");
        assert_eq!(
            candidate_of(valid.as_bytes(), sender),
            Some(Ipv4Addr::LOCALHOST)
        );
        let tolerant = valid
            .replace("LOCATION: ", "location:  ")
            .replace("ST:", "st:");
        assert!(candidate_of(tolerant.as_bytes(), sender).is_some());
        for invalid in [
            valid.replace("200 OK", "500 Error"),
            valid.replace("200 OK", "2000 OK"),
            valid.replace("HTTP/1.1 200 OK", "NOTIFY * HTTP/1.1"),
            valid.replace(ST, "ssdp:all"),
            valid.replace("127.0.0.1", "127.0.0.2"),
            valid.replace("127.0.0.1", "localhost"),
            valid.replace("http://", "https://"),
            valid.replace("127.0.0.1", "user@127.0.0.1"),
            valid.replace(":1400/", ":0/"),
            valid.replace(":1400/", ":65536/"),
            valid.replace(":1400/", ":1400:80/"),
            valid.replace("LOCATION:", " LOCATION:"),
            valid.replace("\r\n\r\n", &format!("\r\nst: {ST}\r\n\r\n")),
            valid.replace("\r\n\r\n", "\r\nLOCATION: http://127.0.0.1/\r\n\r\n"),
            valid.replace(&format!("ST: {ST}\r\n"), ""),
            valid.trim_end().to_string(),
            format!("HTTP/1.1 200 OK\r\n\r\nLOCATION: http://127.0.0.1/\r\nST: {ST}\r\n"),
        ] {
            assert_eq!(
                candidate_of(invalid.as_bytes(), sender),
                None,
                "{invalid:?}"
            );
        }
        assert_eq!(candidate_of(&[0xff], sender), None);
    }

    #[test]
    fn candidates_are_unique_hosts_and_bounded_in_arrival_order() {
        let mut found = Vec::new();
        for n in 1..=MAX_CANDIDATE_HOSTS + 5 {
            let ip = Ipv4Addr::new(10, 0, 0, n as u8);
            for path in ["a", "b"] {
                let payload = reply(&ip.to_string()).replace("desc.xml", path);
                admit_candidate(
                    &mut found,
                    candidate_of(payload.as_bytes(), SocketAddr::new(ip.into(), 1900)).unwrap(),
                );
            }
        }
        assert_eq!(found.len(), MAX_CANDIDATE_HOSTS);
        assert_eq!(found[0], Ipv4Addr::new(10, 0, 0, 1));
        assert_eq!(
            found[MAX_CANDIDATE_HOSTS - 1],
            Ipv4Addr::new(10, 0, 0, MAX_CANDIDATE_HOSTS as u8)
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

    #[test]
    fn sustained_traffic_preserves_deadline_and_sparse_responder() {
        use std::sync::Arc;
        use std::sync::atomic::{AtomicBool, Ordering};
        use std::thread;

        for payload in [
            b"invalid advertisement".to_vec(),
            reply("127.0.0.1").into_bytes(),
        ] {
            let mut poll = Poll::new().unwrap();
            let (busy, busy_addr) = bind_and_register(&mut poll, 0);
            let (sparse, sparse_addr) = bind_and_register(&mut poll, 1);
            let stop = Arc::new(AtomicBool::new(false));
            let sender_stop = stop.clone();
            let flood = thread::spawn(move || {
                let tx = StdUdpSocket::bind("127.0.0.1:0").unwrap();
                tx.set_nonblocking(true).unwrap();
                let until = Instant::now() + Duration::from_secs(2);
                while !sender_stop.load(Ordering::Relaxed) && Instant::now() < until {
                    let _ = tx.send_to(&payload, busy_addr);
                }
            });
            let sparse_sender = thread::spawn(move || {
                let tx = StdUdpSocket::bind("127.0.0.2:0").unwrap();
                thread::sleep(Duration::from_millis(50));
                tx.send_to(reply("127.0.0.2").as_bytes(), sparse_addr)
                    .unwrap();
            });
            let start = Instant::now();
            let result = collect_until(
                &mut poll,
                &[busy, sparse],
                start + Duration::from_millis(400),
            );
            let elapsed = start.elapsed();
            stop.store(true, Ordering::Relaxed);
            flood.join().unwrap();
            sparse_sender.join().unwrap();
            assert!(
                elapsed < Duration::from_secs(1),
                "receive deadline overrun: {elapsed:?}"
            );
            assert!(result.unwrap().contains(&Ipv4Addr::new(127, 0, 0, 2)));
        }
    }

    #[test]
    fn oversized_datagram_is_not_admitted() {
        let mut poll = Poll::new().unwrap();
        let (socket, addr) = bind_and_register(&mut poll, 0);
        let tx = StdUdpSocket::bind("127.0.0.1:0").unwrap();
        let mut payload = reply("127.0.0.1");
        payload.push_str(&"x".repeat(3000));
        tx.send_to(payload.as_bytes(), addr).unwrap();
        assert!(
            collect_until(
                &mut poll,
                &[socket],
                Instant::now() + Duration::from_millis(50)
            )
            .unwrap()
            .is_empty()
        );
    }

    #[test]
    fn queued_reply_after_batch_is_drained_without_another_send() {
        let mut poll = Poll::new().unwrap();
        let (socket, addr) = bind_and_register(&mut poll, 0);
        let tx = StdUdpSocket::bind("127.0.0.1:0").unwrap();
        for _ in 0..RECEIVE_BATCH + 1 {
            tx.send_to(b"invalid", addr).unwrap();
        }
        tx.send_to(reply("127.0.0.1").as_bytes(), addr).unwrap();
        let found = collect_until(
            &mut poll,
            &[socket],
            Instant::now() + Duration::from_millis(100),
        )
        .unwrap();
        assert_eq!(found, vec![Ipv4Addr::LOCALHOST]);
    }

    /// Regression guard for the v0.1 [P1] multi-NIC discovery bug: with
    /// the prior design the recv loop blocked on the first socket until
    /// the global deadline, so a second interface's reply was never read.
    /// `collect_until` must surface replies from *both* sockets.
    ///
    /// Localhost only (127.0.0.1) - NOT the Sonos LAN, so allowed in
    /// sandbox/CI per AGENTS.md §5. The mio recv path returns the
    /// moment either socket has data; the only real latency is the
    /// sender's 50 ms inter-send delay. The test's deadline is its
    /// effective wall-time cap - 400 ms comfortably covers 50 ms of
    /// delay plus scheduler jitter while staying well under the 1 s gate.
    #[test]
    fn collect_until_round_robins_across_all_sockets() {
        use std::thread;

        let mut poll = Poll::new().expect("poll");
        let (sock_a, addr_a) = bind_and_register(&mut poll, 0);
        let (sock_b, addr_b) = bind_and_register(&mut poll, 1);

        let sender = thread::spawn(move || {
            let tx = StdUdpSocket::bind("127.0.0.1:0").expect("bind sender");
            let reply_a = reply("127.0.0.1");
            let tx_b = StdUdpSocket::bind("127.0.0.2:0").expect("bind B");
            let reply_b = reply("127.0.0.2");
            tx.send_to(reply_a.as_bytes(), addr_a).expect("send A");
            // Slight delay before B's reply makes the "stuck on first
            // socket" failure mode observable while staying deterministic
            // and well inside the deadline.
            thread::sleep(Duration::from_millis(50));
            tx_b.send_to(reply_b.as_bytes(), addr_b).expect("send B");
        });

        let found = collect_until(
            &mut poll,
            &[sock_a, sock_b],
            Instant::now() + Duration::from_millis(400),
        )
        .expect("collect_until");
        sender.join().expect("join sender thread");

        assert!(
            found.contains(&Ipv4Addr::LOCALHOST),
            "missing socket A's LOCATION; found={found:?}"
        );
        assert!(
            found.contains(&Ipv4Addr::new(127, 0, 0, 2)),
            "missing socket B's LOCATION (the [P1] failure mode: \
             stuck on the first socket); found={found:?}"
        );
    }

    /// Regression guard for the "wall time stays O(timeout)" contract: a
    /// socket that only ever times out (nothing is ever sent to it) must
    /// not push `collect_until` meaningfully past its deadline. With the
    /// mio path the wait is collective - `poll()` returns the moment the
    /// deadline elapses with no work to do, so the overshoot is bounded
    /// by scheduler granularity rather than any per-socket timeout.
    #[test]
    fn collect_until_does_not_overshoot_deadline() {
        let mut poll = Poll::new().expect("poll");
        let (sock, _addr) = bind_and_register(&mut poll, 0);

        let start = Instant::now();
        let found = collect_until(&mut poll, &[sock], start + Duration::from_millis(300))
            .expect("collect_until");
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
    /// assertion. Localhost only - allowed in sandbox/CI per AGENTS.md §5.
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
            let reply = reply("127.0.0.1");
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
        )
        .expect("collect_until");
        sender.join().expect("join sender thread");

        assert!(
            found.contains(&Ipv4Addr::LOCALHOST),
            "responder behind 13 quiet sockets was not received within the deadline; \
             a regression to the per-socket-timeout design would block long enough \
             to miss it. found={found:?}"
        );
    }
}
