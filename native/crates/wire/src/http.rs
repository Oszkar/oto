//! Blocking HTTP GET for UPnP device descriptions via ureq.
//! ureq handles chunked transfer-encoding and Content-Length transparently;
//! Sonos devices reply HTTP/1.1 with Transfer-Encoding: chunked, which a
//! raw TcpStream GET cannot de-chunk (returns chunk-framed bytes verbatim,
//! causing DeviceDescription::from_xml to fail with a ParseError).

use std::time::Duration;

use oto_core::WireError;

/// GET `url` (expects `http://host:port/path`), return the decoded response body.
///
/// Uses ureq (already in the locked dependency graph via sonos-sdk — no new
/// supply-chain) which transparently handles chunked transfer-encoding and
/// Content-Length. `timeout` bounds **both** the TCP connect phase and the
/// overall request (read/write); a per-call `AgentBuilder` is used so that
/// `AgentBuilder::timeout_connect(timeout)` (connect deadline) and
/// `AgentBuilder::timeout(timeout)` (overall deadline) are both applied.
///
/// This restores the contract of the original raw-TcpStream implementation:
/// a device that stops responding after SSDP discovery cannot stall the
/// caller for longer than `timeout` at the connect phase either. Without
/// the per-call agent, `Request::timeout` does not bound connect (ureq's
/// agent-level connect default is ~30 s), which would blow the discovery
/// budget when a flaky device is targeted.
pub fn get_body(url: &str, timeout: Duration) -> Result<String, WireError> {
    let agent = ureq::AgentBuilder::new()
        .timeout_connect(timeout)
        .timeout(timeout)
        .build();

    let response = agent
        .get(url)
        .call()
        .map_err(|e| WireError::Backend(format!("HTTP GET {url}: {e}")))?;

    response
        .into_string()
        .map_err(|e| WireError::Backend(format!("HTTP body read {url}: {e}")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read as _, Write as _};
    use std::net::TcpListener;
    use std::thread;
    use std::time::Duration;

    /// Spawns a local HTTP server that replies with a hardcoded HTTP/1.1
    /// chunked response. The body encodes a small XML string that includes a
    /// multibyte UTF-8 character (`Küche`) split deliberately across a chunk
    /// boundary. Returns the ephemeral port the server is listening on.
    ///
    /// The server handles exactly ONE connection then exits.
    fn spawn_chunked_server() -> u16 {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let port = listener.local_addr().expect("addr").port();

        thread::spawn(move || {
            let (mut stream, _) = listener.accept().expect("accept");

            // Drain the request (we don't need to parse it).
            let mut buf = [0u8; 4096];
            let _ = stream.read(&mut buf);

            // The body we want the client to receive after de-chunking:
            //   <r><n>Küche</n></r>
            // UTF-8 bytes: K=0x4B ü=0xC3 0xBC c=0x63 h=0x68 e=0x65
            //
            // Split so that ü (0xC3 0xBC) straddles chunk 1/2:
            //   chunk 1: "<r><n>K" + first byte of ü (0xC3)  — 8 bytes
            //   chunk 2: second byte of ü (0xBC) + "che</n></r>"  — 12 bytes
            let part1: &[u8] = b"<r><n>K\xC3"; // 8 bytes  → hex "8"
            let part2: &[u8] = b"\xBCche</n></r>"; // 12 bytes → hex "c"

            let response = format!(
                "HTTP/1.1 200 OK\r\n\
                 Content-Type: text/xml; charset=utf-8\r\n\
                 Transfer-Encoding: chunked\r\n\
                 Connection: close\r\n\
                 \r\n\
                 {:x}\r\n",
                part1.len()
            );
            stream
                .write_all(response.as_bytes())
                .expect("write header+chunk1-size");
            stream.write_all(part1).expect("write chunk1 data");
            stream.write_all(b"\r\n").expect("write chunk1 CRLF");

            let chunk2_header = format!("{:x}\r\n", part2.len());
            stream
                .write_all(chunk2_header.as_bytes())
                .expect("write chunk2 size");
            stream.write_all(part2).expect("write chunk2 data");
            stream.write_all(b"\r\n").expect("write chunk2 CRLF");

            // Terminating chunk.
            stream
                .write_all(b"0\r\n\r\n")
                .expect("write terminating chunk");
            stream.flush().expect("flush");
        });

        port
    }

    /// Regression guard: ureq must de-chunk HTTP/1.1 chunked responses and
    /// correctly reassemble multibyte UTF-8 characters split across chunk
    /// boundaries. The raw TcpStream implementation failed this test with
    /// `Err(Backend("stream did not contain valid UTF-8"))`.
    #[test]
    fn decodes_chunked_response_with_multibyte_utf8_across_chunk_boundary() {
        let port = spawn_chunked_server();
        let url = format!("http://127.0.0.1:{port}/x");

        let result = get_body(&url, Duration::from_secs(2));

        assert!(
            result.is_ok(),
            "get_body should succeed on a chunked response; got: {result:?}"
        );
        let body = result.unwrap();
        assert_eq!(
            body, "<r><n>Küche</n></r>",
            "body should be the fully de-chunked, UTF-8 decoded string; got: {body:?}"
        );
    }
}
