//! Minimal blocking HTTP/1.0 GET for UPnP device descriptions. Raw
//! TcpStream keeps oto-wire free of an HTTP-client dependency.

use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::Duration;

use oto_core::WireError;

/// GET `url` (expects `http://host:port/path`), return the response body.
pub fn get_body(url: &str, timeout: Duration) -> Result<String, WireError> {
    let rest = url
        .strip_prefix("http://")
        .ok_or_else(|| WireError::Backend(format!("non-http LOCATION: {url}")))?;
    let (authority, path) = match rest.split_once('/') {
        Some((a, p)) => (a, format!("/{p}")),
        None => (rest, "/".to_string()),
    };
    let mut stream = TcpStream::connect(authority)
        .map_err(|e| WireError::Backend(format!("connect {authority}: {e}")))?;
    stream
        .set_read_timeout(Some(timeout))
        .and_then(|_| stream.set_write_timeout(Some(timeout)))
        .map_err(|e| WireError::Backend(e.to_string()))?;
    let req = format!(
        "GET {path} HTTP/1.0\r\nHost: {authority}\r\n\
         Connection: close\r\nUser-Agent: oto/0.1\r\n\r\n"
    );
    stream
        .write_all(req.as_bytes())
        .map_err(|e| WireError::Backend(e.to_string()))?;
    let mut raw = String::new();
    stream
        .read_to_string(&mut raw)
        .map_err(|e| WireError::Backend(e.to_string()))?;
    let body = raw
        .split_once("\r\n\r\n")
        .map(|(_, b)| b.to_string())
        .ok_or_else(|| WireError::Backend("malformed HTTP response".into()))?;
    Ok(body)
}
