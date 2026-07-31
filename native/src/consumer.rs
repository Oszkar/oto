//! The v0.4 event-consumer loop.
//!
//! Extracted from `api::subscribe_change_events` so it can be driven by a
//! test without an FRB `StreamSink`. The FRB entry point stays a thin
//! wrapper: it takes the `(generation, rx)` pair out of `oto_app` and hands
//! the loop a `send` closure that does the DTO conversion and `sink.add`.
//!
//! Everything risky lives here - the dual-channel drain, the per-generation
//! stale guard, `Disconnected` teardown, and cancel detection - which is
//! exactly what `native/tests/event_consumer_e2e.rs` exercises.
//!
//! Note this loop is mirrored, deliberately, by
//! `oto_app::test_helpers::process_pending_events`: that helper is a
//! synchronous stand-in used by command-then-read tests. The two are
//! separate implementations and can drift, which is another reason the real
//! one needs its own coverage.

use std::sync::mpsc::{Receiver, RecvTimeoutError};
use std::time::Duration;

use oto_core::ChangeEvent;

/// Why [`run_event_consumer`] returned.
///
/// Production ignores the value (every arm means "this consumer is done"),
/// but distinguishing them is what makes the loop testable: `Cancelled` and
/// `GenerationBumped` are both a `false` out of `send`/the stale guard, and
/// conflating them would leave the stale-guard path unobservable.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConsumerExit {
    /// The Dart subscriber went away - `send` reported the sink is closed.
    Cancelled,
    /// A `discover_with` installed a new wire and bumped the generation past
    /// the one this consumer is paired with. Any remaining event on this
    /// channel is stale by construction.
    GenerationBumped,
    /// The wire's `Sender` dropped: the wire was replaced and its pump
    /// joined. The FRB stream completes and Dart rebuilds.
    Disconnected,
}

/// How long the loop blocks on the wire channel before re-draining the app
/// bus. Coarse on purpose so an idle stream doesn't busy-wake (review
/// #67-followup #6: a 10 ms poll span at 100 Hz when nothing's happening).
/// 250 ms bounds both the app-bus re-drain cadence and teardown-detection
/// latency - fine, app events are degraded-state flags, not real-time, and
/// teardown is not latency-critical. When events flow, the inner drain and
/// the `Ok` arm keep the loop hot regardless.
pub const POLL_SPAN: Duration = Duration::from_millis(250);

/// Drain the app-event bus and `rx` onto one stream until the subscriber
/// cancels, the generation moves, or the wire's sender drops.
///
/// `generation` is the wire generation `rx` was taken with (as one atomic
/// pair, under a single slot lock - see
/// `oto_app::take_event_stream_with_generation`). `send` forwards one event
/// to the subscriber and returns `false` once that subscriber is gone.
///
/// `poll` is the wire-channel block span; production passes [`POLL_SPAN`]
/// and tests pass something short so the teardown paths don't cost a
/// quarter second each.
pub fn run_event_consumer(
    generation: u64,
    rx: &Receiver<ChangeEvent>,
    poll: Duration,
    mut send: impl FnMut(ChangeEvent) -> bool,
) -> ConsumerExit {
    // Apply one event to the cache, then forward it. `Some(exit)` means the
    // caller must stop, for either reason below.
    let mut emit = |event: ChangeEvent| -> Option<ConsumerExit> {
        oto_app::apply_event_at_generation(generation, &event);
        // Stale-wire guard for the Dart side. This consumer's `rx` is paired
        // with `generation`; once a rediscover/refresh bumps the StateManager
        // past it, every remaining event on this OLD-wire channel is stale by
        // construction. The cache apply above already no-ops on the gen
        // mismatch, but the DTO must ALSO be withheld from Dart: the Dart
        // `applyEvent`/`householdProvider` fold has NO generation awareness, so
        // in the window between the Rust bump and the Dart stream re-subscribe
        // a stale Volume/Playback/Track would otherwise land in the UI state.
        if generation != oto_app::current_generation() {
            return Some(ConsumerExit::GenerationBumped);
        }
        if send(event) {
            None
        } else {
            Some(ConsumerExit::Cancelled)
        }
    };

    loop {
        // Exit as soon as our wire is replaced, even if no event arrives to
        // trip the guard inside `emit`. Without this, an idle old-wire channel
        // would keep this FRB worker parked on `recv_timeout` (one `poll` span
        // at a time) until the old pump joins and drops its Sender. The Dart
        // provider re-subscribes on the new generation, so there is nothing
        // left for this consumer to do once the generation has moved.
        if generation != oto_app::current_generation() {
            return ConsumerExit::GenerationBumped;
        }
        // Drain TWO sources onto the one FRB stream (v0.5):
        //   1. oto-app's sibling bus - SubscriptionError/Recovered emitted
        //      on command-dispatch health transitions,
        //   2. the wire's v0.4 channel (`rx`) - property events from the
        //      pump; its `Disconnected` is the teardown signal (wire
        //      replaced on discover() → stream completes → Dart rebuilds).
        //
        // Drain the app bus FIRST, fully, every iteration - otherwise a
        // busy wire channel could starve app events indefinitely (review
        // #65). Drain at OUR generation so a stale event from an old wire
        // is dropped, not forwarded onto this stream (review #67-followup
        // #3). The app bus never disconnects (it's process-global), so only
        // the wire channel drives loop exit.
        while let Some(event) =
            oto_app::try_recv_app_event(generation, oto_app::current_generation())
        {
            if let Some(exit) = emit(event) {
                return exit;
            }
        }
        match rx.recv_timeout(poll) {
            Ok(event) => {
                if let Some(exit) = emit(event) {
                    return exit;
                }
            }
            Err(RecvTimeoutError::Timeout) => continue,
            Err(RecvTimeoutError::Disconnected) => return ConsumerExit::Disconnected,
        }
    }
}
