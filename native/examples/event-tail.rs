//! v0.4 dogfood binary — subscribes to GENA property events on the
//! current LAN and prints each to stdout as it arrives. Not a
//! user-facing CLI; this is the long-running harness behind
//! spec § 8.7–§ 8.9 (≥ 30 min idle, ≥ 30 min active, renewal cycle).
//!
//! Usage:
//!   cargo run --example event-tail            # in `native/`
//!   # Ctrl-C to exit.
//!
//! Acceptance evidence: redirect stdout to a file and let it run
//! through one renewal cycle (~25 min, see spike finding § sonos-notes
//! / `live_events::renewal_cycle_observation`):
//!   cargo run --example event-tail > evidence/v0.4-active.log 2>&1
//!
//! Output format (one line per event):
//!   [<elapsed_s>] <Variant> <id> → <value>
//!
//! Diagnostic stderr lines are prefixed `[event-tail]` so they stand
//! out from the event stream itself.

use std::time::{Duration, Instant};

use oto_core::{ChangeEvent, Wire};
use oto_wire::SonosWire;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let wire = SonosWire::new();
    eprintln!("[event-tail] discovering …");
    let snap = wire.discover()?;
    eprintln!(
        "[event-tail] discovered {} speakers in {} groups",
        snap.speakers.len(),
        snap.groups.len()
    );
    for s in &snap.speakers {
        eprintln!("[event-tail]   speaker {} ({})", s.id, s.room_name);
    }
    for g in &snap.groups {
        eprintln!(
            "[event-tail]   group   {} coord={} members={}",
            g.id,
            g.coordinator,
            g.members.len()
        );
    }

    wire.subscribe_speakers()?;
    let rx = wire
        .take_event_stream()
        .ok_or("subscribe_speakers succeeded but no event stream is available")?;
    eprintln!("[event-tail] subscribed; printing events. Ctrl-C to exit.");

    let start = Instant::now();
    loop {
        // 60 s idle ping cadence — lets a long-running session show
        // "we're still alive" without spamming the log, and any
        // renewal-cycle anomaly (subscriptions silently dropping) shows
        // up as a sustained gap with no idle pings or events.
        match rx.recv_timeout(Duration::from_secs(60)) {
            Ok(event) => {
                let elapsed = start.elapsed().as_secs();
                print_event(elapsed, &event);
            }
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                eprintln!("[event-tail] {}s idle …", start.elapsed().as_secs());
            }
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                eprintln!("[event-tail] sender dropped — exiting");
                break;
            }
        }
    }
    Ok(())
}

/// One-line print per ChangeEvent. Fixed column widths so a long-run
/// log stays scannable. Variant order matches `oto_core::ChangeEvent`.
fn print_event(t: u64, event: &ChangeEvent) {
    match event {
        ChangeEvent::Volume { speaker, volume } => {
            println!("[{t:>5}s] Volume   {speaker}  → {}", volume.get());
        }
        ChangeEvent::Mute { speaker, muted } => {
            println!("[{t:>5}s] Mute     {speaker}  → {muted}");
        }
        ChangeEvent::Playback { group, state } => {
            println!("[{t:>5}s] Playback {group}  → {state:?}");
        }
        ChangeEvent::Track { group, track } => {
            println!(
                "[{t:>5}s] Track    {group}  → {} ({})",
                track.title.as_deref().unwrap_or("(no title)"),
                track.artist.as_deref().unwrap_or("(no artist)"),
            );
        }
        ChangeEvent::SubscriptionError { speaker, message } => {
            // To stderr so it doesn't get lost in a stdout-redirected
            // session capture, and so the production-vs-failure
            // distinction is visible at a glance.
            eprintln!("[{t:>5}s] SubErr   {speaker}  → {message}");
        }
        ChangeEvent::SubscriptionRecovered { speaker } => {
            eprintln!("[{t:>5}s] SubOK    {speaker}");
        }
    }
}
