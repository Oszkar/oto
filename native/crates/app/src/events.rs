//! App-originated event bus (v0.5).
//!
//! `SubscriptionError` / `SubscriptionRecovered` events originate in
//! `oto-app` on conclusive command-dispatch results - NOT in the wire's
//! pump - so they need a path to the FRB consumer independent of the wire's
//! v0.4 `mpsc` channel.
//!
//! **Design.** A process-global sibling channel
//! owned by `oto-app`. The wire's own channel is left untouched: its
//! drop-closes-the-stream teardown signal (v0.4) is load-bearing - when the
//! wire is replaced, its pump's `Sender` drops, the FRB consumer's wire
//! `recv()` returns `Disconnected`, the FRB stream completes, and the Dart
//! provider rebuilds against the new wire. The FRB consumer drains BOTH:
//! it blocks (with a short timeout) on the wire channel - whose
//! `Disconnected` still drives teardown - and polls this sibling channel
//! via `try_recv` (fully, every iteration, so a busy wire can't starve it).
//!
//! **Receiver lives behind a `Mutex` for the bus's whole life - NOT taken.**
//! The FRB consumer restarts on every wire replacement, so a take-once
//! receiver would be lost after the first rediscover (the second consumer
//! could never re-take it). Borrowing it per-poll behind a `Mutex` survives
//! consumer restarts with no take/restore race. (This is a deliberate
//! deviation from the plan's `take_receiver()` sketch, which had that gap.)
//! `Mutex<Receiver<ChangeEvent>>` is `Sync` (Receiver is `Send`), and
//! `Sender<ChangeEvent>` is `Sync` on the workspace MSRV (Rust ≥ 1.72), so
//! `push` from concurrent command threads needs no extra guard.

use std::sync::{
    Mutex, OnceLock,
    mpsc::{self, Receiver, Sender},
};

use oto_core::ChangeEvent;

/// Each event carries the wire **generation** it was emitted under (the
/// `StateManager` generation, bumped per successful `discover_with`). The
/// FRB consumer captures its generation when it starts against a wire and
/// drops any app event stamped with a different one - so a stale
/// `SubscriptionError`/`Recovered` from an OLD wire (still queued, or pushed
/// by a lingering old-wire command) can't surface on the NEW stream after a
/// rediscover (codex cumulative-review #3).
struct Bus {
    tx: Sender<(u64, ChangeEvent)>,
    rx: Mutex<Receiver<(u64, ChangeEvent)>>,
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

/// Push an app-originated event stamped with the current wire `generation`.
/// Fire-and-forget: the send can only fail if the receiver were dropped,
/// which never happens (the bus is `'static`).
pub(crate) fn push(generation: u64, event: ChangeEvent) {
    let _ = bus().tx.send((generation, event));
}

/// Non-blocking drain of the next app-originated event whose stamp matches
/// `consumer_gen` (the wire generation the calling FRB consumer belongs to).
/// Events stamped with a different generation are stale - drained and
/// dropped here so they never reach the new stream. `None` once the channel
/// has no matching event left this tick.
///
/// **Only the CURRENT-generation consumer may drain.** The bus has a single
/// shared receiver. After a rediscover, a lingering OLD-generation consumer
/// keeps looping until its wire channel disconnects; if it drained here it
/// would consume-and-discard events stamped for the NEW generation before the
/// new consumer ever reads them. So a consumer whose `consumer_gen` no longer
/// equals the live generation does not drain at all - it returns `None` and
/// exits soon after on its wire channel's `Disconnected`. (Any events still
/// queued against the old generation were already dropped by [`clear`] in
/// `discover_with`.)
///
/// `current_gen` is a **closure read UNDER the receiver lock**, not a value,
/// mirroring `HealthTracker::observe`. Reading it before taking the lock left
/// a window: an old consumer could read a still-matching generation, have
/// `discover_with` bump and [`clear`] in between, then take the lock and drain
/// a NEW-generation event straight into the stale-drop below - losing a
/// `SubscriptionError`/`Recovered` the new consumer should have seen. Under
/// the lock the window closes in both directions: `discover_with` bumps the
/// generation BEFORE it calls [`clear`], so a replacement either lands before
/// we read (the check fails, we do not drain) or blocks on [`clear`] until we
/// release - and while we hold the lock the new wire is not in the slot yet,
/// so no new-generation event can even be pushed.
pub fn try_recv_app_event(consumer_gen: u64, current_gen: impl Fn() -> u64) -> Option<ChangeEvent> {
    let rx = bus().rx.lock().unwrap_or_else(|p| p.into_inner());
    if consumer_gen != current_gen() {
        return None;
    }
    while let Ok((generation, event)) = rx.try_recv() {
        if generation == consumer_gen {
            return Some(event);
        }
        // Stale (different wire era) - drop and keep draining. Only reachable
        // for OLD-generation leftovers now: see the lock note above.
    }
    None
}

/// Test-only probe: `true` while the bus receiver lock is held. Calling it
/// from inside a `try_recv_app_event` `current_gen` closure, on the same
/// thread, is how `generation_is_read_under_the_bus_lock` pins the ordering
/// this module depends on - a value-based test cannot distinguish a read above
/// the lock from one below it. (A poisoned mutex also reads as "locked"; the
/// bus is never poisoned in practice, and a false positive here would only
/// weaken the assertion, never fail it spuriously.)
#[cfg(test)]
pub(crate) fn receiver_is_locked() -> bool {
    bus().rx.try_lock().is_err()
}

/// Drain and discard every pending app-bus event. Called by `discover_with`
/// on wire replacement: any `SubscriptionError` /
/// `Recovered` still queued against the OLD wire is stale and must not
/// surface on the NEW stream after rediscover.
pub(crate) fn clear() {
    let rx = bus().rx.lock().unwrap_or_else(|p| p.into_inner());
    while rx.try_recv().is_ok() {}
}

// No unit tests here: the bus is a process-global singleton, so any
// emptiness/round-trip assertion races other tests that `push()` in the
// same `cargo test` binary (review #65). The push → `try_recv_app_event`
// path is covered end-to-end - via real command-dispatch failures - by the
// `oto-app` integration tests in `lib.rs`, which serialize on
// `TEST_SERIAL`.
