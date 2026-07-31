//! Coverage for the v0.4 event-consumer loop (`oto_native::consumer`), the
//! glue that `api::subscribe_change_events` runs on the FRB worker thread.
//!
//! Its parts are well covered elsewhere (StateManager apply, the health
//! tracker, the app-event bus), but the loop that composes them had no Rust
//! test at any level - only the Flutter `integration_test/` files, which no
//! automation runs. The four behaviors asserted here are the ones with no
//! other backstop:
//!
//! 1. cancel detection - `send` returning `false` stops the loop,
//! 2. `Disconnected` teardown - the wire's Sender dropping ends it cleanly,
//! 3. the per-generation stale guard - a mid-stream `discover_with` withholds
//!    every remaining event from Dart instead of folding it into fresh state,
//! 4. the dual-channel drain order - the app bus is drained FIRST, fully, so
//!    a busy wire channel cannot starve health events (review #65).
//!
//! The loop takes `rx` as a parameter, so these drive their OWN channel
//! rather than the held wire's. That keeps every phase deterministic: no
//! sleeps, no races against the mock's pump.

use std::sync::mpsc::{self, Sender};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use oto_core::{
    ChangeEvent, DiscoverySnapshot, GroupId, SpeakerId, SpeakerState, TrackPosition, Volume, Wire,
    WireError,
};
use oto_mock::MockWire;
use oto_native::consumer::{ConsumerExit, run_event_consumer};

/// Short poll so the teardown paths don't cost a quarter second each.
/// Production uses `consumer::POLL_SPAN` (250 ms).
const TEST_POLL: Duration = Duration::from_millis(10);

/// Wraps `Arc<MockWire>` so a test can keep introspecting / injecting on the
/// mock after `discover_with` boxes it into the slot. Mirrors the `ArcWire`
/// in oto-app's own tests and `MockWireArc` in `api.rs`'s dev seam.
struct ArcWire(Arc<MockWire>);

impl Wire for ArcWire {
    fn discover(&self) -> Result<DiscoverySnapshot, WireError> {
        self.0.discover()
    }
    fn play(&self, g: &GroupId) -> Result<(), WireError> {
        self.0.play(g)
    }
    fn pause(&self, g: &GroupId) -> Result<(), WireError> {
        self.0.pause(g)
    }
    fn next(&self, g: &GroupId) -> Result<(), WireError> {
        self.0.next(g)
    }
    fn previous(&self, g: &GroupId) -> Result<(), WireError> {
        self.0.previous(g)
    }
    fn set_volume(&self, s: &SpeakerId, v: Volume) -> Result<(), WireError> {
        self.0.set_volume(s, v)
    }
    fn set_mute(&self, s: &SpeakerId, m: bool) -> Result<(), WireError> {
        self.0.set_mute(s, m)
    }
    fn set_group_volume(&self, g: &GroupId, v: Volume) -> Result<(), WireError> {
        self.0.set_group_volume(g, v)
    }
    fn set_group_mute(&self, g: &GroupId, m: bool) -> Result<(), WireError> {
        self.0.set_group_mute(g, m)
    }
    fn join_group(&self, s: &SpeakerId, c: &SpeakerId) -> Result<(), WireError> {
        self.0.join_group(s, c)
    }
    fn leave_group(&self, s: &SpeakerId) -> Result<(), WireError> {
        self.0.leave_group(s)
    }
    fn speaker_state(&self, s: &SpeakerId) -> Result<SpeakerState, WireError> {
        self.0.speaker_state(s)
    }
    fn track_position(&self, g: &GroupId) -> Result<TrackPosition, WireError> {
        self.0.track_position(g)
    }
    fn subscribe_speakers(&self) -> Result<(), WireError> {
        self.0.subscribe_speakers()
    }
    fn subscribe_topology(&self) -> Result<(), WireError> {
        self.0.subscribe_topology()
    }
    fn refresh_topology(&self) -> Result<DiscoverySnapshot, WireError> {
        self.0.refresh_topology()
    }
    fn take_event_stream(&self) -> Option<mpsc::Receiver<ChangeEvent>> {
        self.0.take_event_stream()
    }
}

/// Install a fresh MockWire and hand back the handle, so a test can inject
/// command errors on the SAME instance that's in `oto_app`'s slot.
fn install_held_mock() -> Arc<MockWire> {
    let mock = Arc::new(MockWire::default());
    let for_app = Arc::clone(&mock);
    oto_app::discover_with(move || Box::new(ArcWire(for_app)))
        .expect("mock discovery must succeed");
    mock
}

/// Drain whatever is already queued on the app bus at the current
/// generation, so a phase starts from a known-empty bus.
fn drain_app_bus() {
    let generation = oto_app::current_generation();
    while oto_app::try_recv_app_event(generation, oto_app::current_generation()).is_some() {}
}

fn volume_event(speaker: &str, level: u8) -> ChangeEvent {
    ChangeEvent::Volume {
        speaker: SpeakerId::new(speaker),
        volume: Volume::new(level).expect("level in range"),
    }
}

/// Push events onto a test-owned channel, mimicking the wire pump.
fn feed(tx: &Sender<ChangeEvent>, events: Vec<ChangeEvent>) {
    for e in events {
        tx.send(e).expect("test channel receiver is alive");
    }
}

/// One comprehensive test, deliberately. `oto_app` stores its wire in a
/// process-global slot, so separate `#[test]` fns would fight over it under
/// `cargo test` (parallel threads, one process). Same rationale as
/// `playback_e2e.rs`.
#[test]
fn event_consumer_loop_lifecycle() {
    // ── Phase A: events reach the subscriber; `false` from send cancels ────
    let _mock = install_held_mock();
    let generation = oto_app::current_generation();
    drain_app_bus();

    let (tx, rx) = mpsc::channel();
    feed(
        &tx,
        vec![
            volume_event("RINCON_KITCHEN", 10),
            volume_event("RINCON_KITCHEN", 20),
            volume_event("RINCON_KITCHEN", 30),
        ],
    );

    let seen = Mutex::new(Vec::new());
    let exit = run_event_consumer(generation, &rx, TEST_POLL, |event| {
        let mut s = seen.lock().expect("test mutex");
        s.push(event);
        // Simulate the Dart subscriber dropping after the third event.
        s.len() < 3
    });

    assert_eq!(
        exit,
        ConsumerExit::Cancelled,
        "a `false` from send must stop the loop as Cancelled"
    );
    assert_eq!(
        seen.lock().expect("test mutex").len(),
        3,
        "every event before the cancel must reach the subscriber"
    );
    drop(tx);

    // ── Phase B: the wire's Sender dropping tears the loop down cleanly ────
    let generation = oto_app::current_generation();
    let (tx, rx) = mpsc::channel();
    feed(
        &tx,
        vec![
            volume_event("RINCON_OFFICE", 40),
            volume_event("RINCON_OFFICE", 50),
        ],
    );
    // The pump's Sender goes away (wire replaced / pump joined). Buffered
    // events must still drain before the loop notices.
    drop(tx);

    let seen = Mutex::new(Vec::new());
    let exit = run_event_consumer(generation, &rx, TEST_POLL, |event| {
        seen.lock().expect("test mutex").push(event);
        true
    });

    assert_eq!(
        exit,
        ConsumerExit::Disconnected,
        "a dropped Sender must exit as Disconnected, not hang"
    );
    assert_eq!(
        seen.lock().expect("test mutex").len(),
        2,
        "events buffered before the drop must still be delivered"
    );

    // ── Phase C: a mid-stream generation bump withholds the stale events ───
    //
    // This is the guard that keeps a stale Volume/Playback from landing in
    // the UI in the window between the Rust bump and the Dart re-subscribe.
    // The Dart-side fold has no generation awareness, so withholding here is
    // the only thing standing between a replaced wire and corrupted state.
    let generation = oto_app::current_generation();
    let (tx, rx) = mpsc::channel();
    feed(
        &tx,
        vec![
            volume_event("RINCON_DINING", 60),
            volume_event("RINCON_DINING", 70),
        ],
    );

    let seen = Mutex::new(Vec::new());
    let exit = run_event_consumer(generation, &rx, TEST_POLL, |event| {
        let mut s = seen.lock().expect("test mutex");
        s.push(event);
        if s.len() == 1 {
            // A rediscover lands while this consumer is mid-stream. Drop the
            // guard first: `discover_with` re-enters oto_app, and holding a
            // test lock across it buys nothing.
            drop(s);
            install_held_mock();
        }
        true
    });

    assert_eq!(
        exit,
        ConsumerExit::GenerationBumped,
        "a generation bump must exit as GenerationBumped, distinctly from a cancel"
    );
    assert_eq!(
        seen.lock().expect("test mutex").len(),
        1,
        "the event queued behind the bump must be WITHHELD from the subscriber"
    );
    drop(tx);

    // ── Phase D: the app bus is drained before the wire channel ────────────
    //
    // Regression bar for review #65: a busy wire channel must not starve
    // health events. Both sources have something queued; the app-bus event
    // has to come out first.
    let mock = install_held_mock();
    let generation = oto_app::current_generation();
    drain_app_bus();

    let (tx, rx) = mpsc::channel();
    // Queue the wire-channel event FIRST, so ordering can only come from the
    // drain policy rather than from arrival order.
    feed(&tx, vec![volume_event("RINCON_OFFICE", 80)]);

    // Now put a SubscriptionError on the app bus the production way: a
    // command that fails with `Network` flips health and pushes the event.
    let kitchen = SpeakerId::new("RINCON_KITCHEN");
    mock.set_command_error(&kitchen, WireError::Network("unreachable".into()));
    let res = oto_app::set_volume(&kitchen, Volume::new(55).expect("55 in range"));
    assert!(
        matches!(res, Err(WireError::Network(_))),
        "precondition: the injected error must surface as Network"
    );

    let seen = Mutex::new(Vec::new());
    let exit = run_event_consumer(generation, &rx, TEST_POLL, |event| {
        let mut s = seen.lock().expect("test mutex");
        s.push(event);
        s.len() < 2
    });

    assert_eq!(exit, ConsumerExit::Cancelled);
    let seen = seen.into_inner().expect("test mutex");
    assert_eq!(seen.len(), 2, "one app-bus event + one wire event");
    assert!(
        matches!(
            &seen[0],
            ChangeEvent::SubscriptionError { speaker, .. } if *speaker == kitchen
        ),
        "the app bus must drain FIRST - got {:?}",
        seen[0]
    );
    assert!(
        matches!(&seen[1], ChangeEvent::Volume { .. }),
        "the wire event must follow the app-bus event - got {:?}",
        seen[1]
    );
    drop(tx);
}
