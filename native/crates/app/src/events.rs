//! App-originated event bus (v0.5 S2).
//!
//! `SubscriptionError` / `SubscriptionRecovered` events originate in
//! `oto-app` on command-dispatch health transitions — NOT in the wire's
//! pump — so they need a path to the FRB consumer independent of the wire's
//! v0.4 `mpsc` channel.
//!
//! **Design (plan Task 6, approach d1).** A process-global sibling channel
//! owned by `oto-app`. The wire's own channel is left untouched: its
//! drop-closes-the-stream teardown signal (v0.4) is load-bearing — when the
//! wire is replaced, its pump's `Sender` drops, the FRB consumer's wire
//! `recv()` returns `Disconnected`, the FRB stream completes, and the Dart
//! provider rebuilds against the new wire. The FRB consumer drains BOTH:
//! it blocks (with a short timeout) on the wire channel — whose `Disconnect`
//! still drives teardown — and polls this sibling channel via `try_recv`.
//!
//! **Receiver lives behind a `Mutex` for the bus's whole life — NOT taken.**
//! The FRB consumer restarts on every wire replacement, so a take-once
//! receiver would be lost after the first rediscover (the second consumer
//! could never re-take it). Borrowing it per-poll behind a `Mutex` survives
//! consumer restarts with no take/restore race. (This is a deliberate
//! deviation from the plan's `take_receiver()` sketch, which had that gap.)
//! `Mutex<Receiver<ChangeEvent>>` is `Sync` (Receiver is `Send`), and
//! `Sender<ChangeEvent>` is `Sync` on the workspace MSRV (Rust ≥ 1.72), so
//! `push` from concurrent command threads needs no extra guard.

use std::sync::{
    mpsc::{self, Receiver, Sender},
    Mutex, OnceLock,
};

use oto_core::ChangeEvent;

struct Bus {
    tx: Sender<ChangeEvent>,
    rx: Mutex<Receiver<ChangeEvent>>,
}

fn bus() -> &'static Bus {
    static BUS: OnceLock<Bus> = OnceLock::new();
    BUS.get_or_init(|| {
        let (tx, rx) = mpsc::channel();
        Bus {
            tx,
            rx: Mutex::new(rx),
        }
    })
}

/// Push an app-originated event onto the sibling channel. Fire-and-forget:
/// the send can only fail if the receiver were dropped, which never happens
/// (the bus is `'static`).
pub(crate) fn push(event: ChangeEvent) {
    let _ = bus().tx.send(event);
}

/// Non-blocking drain of one app-originated event, for the FRB consumer to
/// interleave with the wire channel. `None` if the channel is empty
/// (`Disconnected` is unreachable — the `'static` bus keeps a `Sender`).
pub fn try_recv_app_event() -> Option<ChangeEvent> {
    bus()
        .rx
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .try_recv()
        .ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use oto_core::SpeakerId;

    #[test]
    fn push_then_try_recv_round_trips() {
        push(ChangeEvent::SubscriptionRecovered {
            speaker: SpeakerId::new("RINCON_BUS_TEST"),
        });
        // Drain until we see our event (the bus is process-global; other
        // tests in this binary may have pushed too — match on our id).
        let mut seen = false;
        while let Some(ev) = try_recv_app_event() {
            if matches!(ev, ChangeEvent::SubscriptionRecovered { speaker } if speaker.as_str() == "RINCON_BUS_TEST")
            {
                seen = true;
            }
        }
        assert!(
            seen,
            "pushed event must be drainable via try_recv_app_event"
        );
    }

    #[test]
    fn try_recv_is_none_when_empty() {
        // Drain anything pending first, then assert empty.
        while try_recv_app_event().is_some() {}
        assert!(try_recv_app_event().is_none());
    }
}
