//! Fetch + parse Sonos `device_description.xml` for the `model` field
//! (v0.5). ZoneGroupTopology carries no model attribute (oto-core D1),
//! so `SpeakerIdentity.model` was `None` from v0.3; `discover()` and
//! `refresh_topology()` repopulate it from each speaker's HTTP device
//! description.
//!
//! Per `docs/sonos-notes.md` § SSDP "HTTP fetch quirk": Sonos's embedded
//! server replies `Transfer-Encoding: chunked` (no `Content-Length`) even
//! to an HTTP/1.0 request, which a raw `TcpStream` mis-frames. `ureq`
//! handles chunked + UTF-8 and bounds connect/read timeouts with a
//! blocking, runtime-free API. Fetches are best-effort: any failure
//! (timeout, network, parse) yields `None` for that speaker — discovery
//! does NOT fail, the speaker just keeps `model = None`.

use std::collections::HashMap;
use std::net::IpAddr;
use std::time::Duration;

use oto_core::SpeakerId;
use quick_xml::events::Event;
use quick_xml::Reader;

/// Per-speaker connect timeout. Short — the speaker is on the LAN and was
/// just reached for ZGT; a slow connect means it's gone, skip it.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(1);
/// Per-speaker overall read timeout. The document is tiny (a few KB).
const READ_TIMEOUT: Duration = Duration::from_secs(2);

/// Fetch `device_description.xml` from `ip` and extract `<modelName>`.
/// `None` on any error (timeout, network, parse) — the caller treats this
/// as "model unknown for this speaker" and does not fail discovery.
fn fetch_model(ip: IpAddr) -> Option<String> {
    let url = format!("http://{ip}:1400/xml/device_description.xml");
    let agent = ureq::AgentBuilder::new()
        .timeout_connect(CONNECT_TIMEOUT)
        .timeout(READ_TIMEOUT)
        .build();
    let body = agent.get(&url).call().ok()?.into_string().ok()?;
    parse_model_name(&body)
}

/// Extract the text of the first `<modelName>` element. The device
/// description nests it under `<device>`; the first occurrence is the
/// top-level device's model (satellites would be deeper, but we only fetch
/// surfaced primaries).
fn parse_model_name(xml: &str) -> Option<String> {
    let mut reader = Reader::from_str(xml);
    reader.trim_text(true);
    let mut buf = Vec::new();
    let mut in_model = false;
    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(e)) if e.name().as_ref() == b"modelName" => in_model = true,
            Ok(Event::Text(t)) if in_model => return Some(t.unescape().ok()?.into_owned()),
            Ok(Event::End(e)) if e.name().as_ref() == b"modelName" => in_model = false,
            Ok(Event::Eof) | Err(_) => return None,
            _ => {}
        }
        buf.clear();
    }
}

/// Max concurrent fetches. A real household is a handful of speakers (one
/// chunk = the old "all at once" behaviour, latency ≈ the slowest fetch).
/// The cap bounds thread creation if a malformed/hostile ZoneGroupTopology
/// ever yields an absurd member count (codex review #67-followup #7) — no
/// silent truncation, just bounded concurrency across sequential chunks.
const MAX_CONCURRENT_FETCHES: usize = 8;

/// Fetch `<modelName>` for each `(speaker_id, ip)` in parallel, at most
/// `MAX_CONCURRENT_FETCHES` at a time (scoped threads per chunk). Returns
/// only the speakers whose fetch succeeded; the rest are absent (caller
/// leaves their `model = None`). A panicking fetch thread is dropped, not
/// propagated — one bad speaker can't fail discovery.
pub(crate) fn fetch_models_parallel(targets: &[(SpeakerId, IpAddr)]) -> HashMap<SpeakerId, String> {
    let mut out = HashMap::new();
    for chunk in targets.chunks(MAX_CONCURRENT_FETCHES) {
        let batch: Vec<(SpeakerId, String)> = std::thread::scope(|scope| {
            let handles: Vec<_> = chunk
                .iter()
                .map(|(sid, ip)| {
                    let sid = sid.clone();
                    let ip = *ip;
                    scope.spawn(move || fetch_model(ip).map(|model| (sid, model)))
                })
                .collect();
            handles
                .into_iter()
                .filter_map(|h| h.join().ok().flatten())
                .collect()
        });
        out.extend(batch);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_model_name_extracts_modelname() {
        let xml = r#"<?xml version="1.0"?>
<root>
  <device>
    <modelName>Sonos Era 100</modelName>
  </device>
</root>"#;
        assert_eq!(parse_model_name(xml).as_deref(), Some("Sonos Era 100"));
    }

    #[test]
    fn parse_model_name_missing_returns_none() {
        let xml = "<root><device></device></root>";
        assert!(parse_model_name(xml).is_none());
    }

    #[test]
    fn parse_model_name_unescapes_entities() {
        let xml = "<root><modelName>Sonos &amp; Co</modelName></root>";
        assert_eq!(parse_model_name(xml).as_deref(), Some("Sonos & Co"));
    }

    #[test]
    fn fetch_models_parallel_empty_targets_is_empty() {
        let out = fetch_models_parallel(&[]);
        assert!(out.is_empty());
    }
}
