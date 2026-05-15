//! Own multi-interface SSDP. sonos-sdk's discovery binds 0.0.0.0 and
//! fails on multi-NIC hosts (spike findings / tatimblin/sonos-sdk#76);
//! we enumerate interfaces and bind each explicitly.

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

/// SSDP across every usable IPv4 interface. Returns unique LOCATION URLs.
///
/// Binds one UDP socket per interface and sends a ZonePlayer M-SEARCH on
/// each. `timeout` is the **total bounded window** across all interfaces:
/// the deadline is computed once before iterating, so wall time stays
/// O(timeout) regardless of NIC count (important on multi-NIC Windows hosts
/// with Docker/WSL/VPN adapters). Interfaces that cannot be bound or cannot
/// egress multicast are skipped; only the `set_read_timeout` system call is
/// fatal (local OS error, not a network condition).
pub fn discover_locations(timeout: Duration) -> Result<Vec<String>, WireError> {
    let ifaces = usable_ipv4()?;
    if ifaces.is_empty() {
        return Err(WireError::Network("no usable IPv4 interface".into()));
    }
    let msearch = msearch();
    let deadline = Instant::now() + timeout;
    let mut found: BTreeSet<String> = BTreeSet::new();
    for ip in ifaces {
        if Instant::now() >= deadline {
            break;
        }
        let sock = match UdpSocket::bind((ip, 0)) {
            Ok(s) => s,
            Err(_) => continue, // adapter unbindable (e.g. some VPN/tunnel) — skip, like send_to failure
        };
        sock.set_read_timeout(Some(Duration::from_millis(800)))
            .map_err(|e| WireError::Network(e.to_string()))?;
        if sock.send_to(msearch.as_bytes(), SSDP_ADDR).is_err() {
            // Interface can't egress multicast (e.g. a virtual adapter with no
            // route to 239.x); skip it and try remaining interfaces.
            continue;
        }
        let mut buf = [0u8; 2048];
        while Instant::now() < deadline {
            match sock.recv_from(&mut buf) {
                Ok((n, _)) => {
                    if let Some(loc) = location_of(&String::from_utf8_lossy(&buf[..n])) {
                        found.insert(loc);
                    }
                }
                Err(e)
                    if e.kind() == std::io::ErrorKind::WouldBlock
                        || e.kind() == std::io::ErrorKind::TimedOut => {}
                Err(_) => break,
            }
        }
    }
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
}
