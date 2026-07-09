//! Throwaway diagnostic - NOT part of the product.
//!
//! Confirms the sonos-sdk-discovery root cause: it binds the SSDP socket to
//! `0.0.0.0`, so on a multi-NIC host the OS may egress the M-SEARCH
//! multicast on the wrong interface (e.g. a WSL/Hyper-V vEthernet) and the
//! speakers never hear it.
//!
//! This probe binds to a *specific* local interface IP and sends the same
//! M-SEARCH. If it finds speakers when bound to the LAN interface but not
//! when bound to `0.0.0.0`, the diagnosis is confirmed and this is also a
//! prototype of the fix.
//!
//! ```text
//! cargo run -p oto-wire --example ssdp_probe -- 10.83.0.10
//! cargo run -p oto-wire --example ssdp_probe -- 0.0.0.0
//! ```

use std::net::UdpSocket;
use std::time::{Duration, Instant};

const SSDP_ADDR: &str = "239.255.255.250:1900";

fn main() {
    let bind_ip = std::env::args().nth(1).unwrap_or_else(|| "0.0.0.0".into());
    let bind_addr = format!("{bind_ip}:0");

    println!("== binding UDP socket to {bind_addr} ==");
    let socket = match UdpSocket::bind(&bind_addr) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("bind({bind_addr}) failed: {e}");
            std::process::exit(1);
        }
    };
    socket
        .set_read_timeout(Some(Duration::from_millis(800)))
        .expect("set_read_timeout");
    if let Ok(local) = socket.local_addr() {
        println!("   local_addr = {local}");
    }

    // Same M-SEARCH sonos-sdk-discovery sends.
    let msearch = "M-SEARCH * HTTP/1.1\r\n\
         HOST: 239.255.255.250:1900\r\n\
         MAN: \"ssdp:discover\"\r\n\
         MX: 2\r\n\
         ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\
         USER-AGENT: oto-spike/0.1 UPnP/1.0\r\n\
         \r\n";

    match socket.send_to(msearch.as_bytes(), SSDP_ADDR) {
        Ok(n) => println!("== sent M-SEARCH ({n} bytes) to {SSDP_ADDR} =="),
        Err(e) => {
            eprintln!("send_to failed: {e}");
            std::process::exit(1);
        }
    }

    println!("== collecting responses for 4s ==");
    let mut buf = [0u8; 2048];
    let deadline = Instant::now() + Duration::from_secs(4);
    let mut found = 0u32;
    while Instant::now() < deadline {
        match socket.recv_from(&mut buf) {
            Ok((size, from)) => {
                let text = String::from_utf8_lossy(&buf[..size]);
                let location = text
                    .lines()
                    .find(|l| l.to_ascii_lowercase().starts_with("location:"))
                    .map(|l| l.trim())
                    .unwrap_or("(no LOCATION header)");
                found += 1;
                println!("  reply #{found} from {from}");
                println!("    {location}");
            }
            Err(e)
                if e.kind() == std::io::ErrorKind::WouldBlock
                    || e.kind() == std::io::ErrorKind::TimedOut => {}
            Err(e) => {
                eprintln!("  recv error: {e}");
                break;
            }
        }
    }

    println!("\n== {found} SSDP responder(s) on interface {bind_ip} ==");
    if found == 0 {
        println!("   (none - wrong interface, or no Sonos reachable here)");
    }
}
