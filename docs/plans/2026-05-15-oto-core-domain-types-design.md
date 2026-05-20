# oto-core domain types — design

**Date:** 2026-05-15 **Branch:** `feat/core-domain-types` **Scope:** Step 1 of the post-scaffold roadmap — define the pure-Rust domain types that every later step (discovery, SOAP, events, UI providers) will reference.

## Goal

Populate `oto-core` with a small set of well-shaped domain types so the next steps have concrete vocabulary. No networking, no async, no third-party deps.

## Non-goals

- Discovery, SOAP, eventing — later steps.
- Modeling bonded speakers (stereo pair, surrounds). Bonded satellites are hidden behind their primary in Sonos's topology; revisit if we ever surface them in the UI.
- `household_id` — only matters for multi-household setups; deferred.
- Queue / playlist state. Lives on `Group` later when transport control lands.
- Sound-shaping fields (bass, treble, balance, crossfade, night mode, etc.).
- Repeat / shuffle modes. Add when we wire transport control.

## Reference implementations consulted

- [SoCo](https://github.com/SoCo/SoCo) (Python) — `groups.py`, `data_structures.py`.
- [Home Assistant Sonos integration](https://github.com/home-assistant/core/tree/dev/homeassistant/components/sonos) — `speaker.py`.
- [sonor](https://docs.rs/sonor/) (Rust) — top-level types.
- [tatimblin/sonos-cli](https://github.com/tatimblin/sonos-cli) + [tatimblin/sonos-sdk](https://github.com/tatimblin/sonos-sdk) — the lib we may pull in for the wire layer.

Key alignment points and deviations are called out under "Decisions" below.

## Module layout

```
crates/core/src/
├── lib.rs           # module mounts + re-exports at crate root
├── error.rs         # Error enum (manual Display/Error impls; no thiserror dep)
├── identifiers.rs   # SpeakerId, GroupId, TrackId
├── volume.rs        # Volume
├── track.rs         # Track
├── transport.rs     # PlaybackState, TransportState
├── speaker.rs       # Speaker
└── group.rs         # Group
```

`lib.rs` re-exports the public surface at the crate root so callers write `use oto_core::{Speaker, Group, Volume};` rather than reaching into modules. The `#![deny(unsafe_code)]` lint stays.

## Type sketches

### Identifiers

Opaque newtypes around `String`. No validation — Sonos `RINCON_…` strings arrive from device descriptions; we trust them. Type-distinct so a `GroupId` can never be passed where a `SpeakerId` is expected.

```rust
pub struct SpeakerId(String);
pub struct GroupId(String);
pub struct TrackId(String);
// each: ::new(impl Into<String>) -> Self, ::as_str(&self) -> &str
// each: From<&str>, From<String>, Display, Debug, Clone, PartialEq, Eq, Hash
```

### Error

One enum lives in `oto-core` for now. Pure manual impls; no `thiserror`.

```rust
pub enum Error {
    InvalidVolume(u8),
}
impl Display, std::error::Error
```

### Volume

Validated newtype. Strict constructor for caller code, lenient `clamped` for SOAP parsing where out-of-range values are clamped instead of rejected.

```rust
pub struct Volume(u8);
impl Volume {
    pub const MIN: Volume = Volume(0);
    pub const MAX: Volume = Volume(100);
    pub fn new(v: u8) -> Result<Self, Error>;     // strict
    pub fn clamped(v: i32) -> Self;               // lenient — for SOAP parsing
    pub fn get(self) -> u8;
}
// Debug, Display, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash
```

### Track

Most fields optional — Sonos returns partial metadata for radio streams, line-in, TV input, etc.

```rust
pub struct Track {
    pub id: Option<TrackId>,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub track_number: Option<u32>,
    pub duration: Option<Duration>,    // std::time::Duration
    pub art_uri: Option<String>,
    pub uri: Option<String>,
}
// Debug, Clone, PartialEq, Eq
```

### Transport

```rust
pub enum PlaybackState { Stopped, Playing, Paused, Transitioning }

pub struct TransportState {
    pub state: PlaybackState,
    pub current_track: Option<Track>,
    pub position: Option<Duration>,    // elapsed within current_track
}
// Debug, Clone, PartialEq, Eq
```

### Speaker

Per-device state only. No transport state here — see Decisions.

```rust
pub struct Speaker {
    pub id: SpeakerId,
    pub room_name: String,             // user-set zone label, e.g. "Kitchen"
    pub model: Option<String>,
    pub ip: IpAddr,                    // std::net::IpAddr
    pub volume: Volume,
    pub muted: bool,
}
// Debug, Clone, PartialEq, Eq
```

### Group

Owns the playback state. Solo speakers are a `Group` with one member; this is honest about Sonos's actual semantics (transport always belongs to the playback unit, not a device).

```rust
pub struct Group {
    pub id: GroupId,
    pub coordinator: SpeakerId,
    pub members: Vec<SpeakerId>,       // includes coordinator first
    pub transport: TransportState,
}
// Debug, Clone, PartialEq, Eq
```

## Decisions

### D1 — Newtypes everywhere (vs. plain primitives)

Identifiers and `Volume` are newtypes with validation where applicable. Trade ~30 lines of boilerplate for compile-time prevention of ID-mix-up bugs and out-of-range volumes. FRB friction is avoided by keeping newtypes core-side and converting to primitives in `native/src/api.rs` at the bridge boundary.

### D2 — Transport lives on `Group`, not `Speaker`

This is the deliberate deviation from SoCo / Home Assistant / sonor / sonos-sdk, all of which put transport on each speaker (duplicated across group members).

**Why on `Group`:**
- Single source of truth — `AVTransport.LastChange` events come from the coordinator and update one place. No member-sync bug class.
- Matches Sonos's event topology directly.
- No "scrub stale transport off ungrouped speaker" step needed.
- Solo speakers form a group of 1, so the model is uniform.

**Cost:** UI rendering needs one indirection (speaker → its group → transport), implemented as a Riverpod `select` provider on the Dart side.

**Alternative considered (revisit if grouping proves painful):** put `transport: TransportState` directly on `Speaker`, drop the `Group` struct entirely until step 6, and add it then. This matches every reference library and removes the "group of 1" boilerplate during steps 2–5. The migration cost later is mechanical (move one field). If our adapter to a third-party Sonos lib feels like fighting the data shape, or if Riverpod wiring grows disproportionate, fall back to this.

### D3 — `members` includes the coordinator (first position)

Matches Sonos's `ZoneGroupTopology` event order. "Iterate all speakers in group" is the dominant operation and benefits from a single list. The "coordinator vs satellite" distinction is recoverable via `members[0] == coordinator` or `id == group.coordinator`.

### D4 — `TransportState` is a struct, not a stateful enum

Sketched alternative was `enum { Playing { track, position }, Paused { … }, Stopped }`. Rejected because Sonos's `Stopped` state still retains the last-loaded track in memory (so the UI can show "Last played: …"). A stateful enum would force inventing a fake/empty track for `Stopped`. Cost: the type allows `Playing` with `current_track: None`, which should never happen in practice — the invariant lives in the parser, not the type.

### D5 — `room_name` over `name`

Matches Sonos's wire vocabulary (`RoomName`). The user-set label *is* the room identifier in Sonos; bonded satellites share their primary's `RoomName` and aren't surfaced as separate entities.

### D6 — Adapter pattern for any third-party Sonos lib

Whatever crate ends up powering steps 2–6 (sonos-sdk, sonor, rusty-sonos, or in-house code) stays behind a `From<lib::T> for oto_core::T` boundary. The domain types in this design don't depend on any library's choices and can be remapped cheaply if we change libraries later.

## Tests

Per-type unit tests under each module's `#[cfg(test)] mod tests`:

- `Volume::new` boundary table: 0, 1, 50, 100, 101, 255.
- `Volume::clamped`: -5, 0, 50, 100, 200.
- Identifier round-trip: `new`, `as_str`, `Display`, `From<&str>`, `From<String>`.
- Construct a fully-populated `Group { coordinator, members: vec![SpeakerId, SpeakerId], transport: TransportState{Playing, Track, Duration} }` to catch accidental private-field regressions.
- One `Error` `Display` snapshot test.

No `proptest` / `quickcheck` / `serde_json` for fixtures — pure deps-free std-only.

## Out of scope for this PR (next steps)

- Wire `oto-core` re-exports through `oto_native::api` so Dart can see the types via FRB. Deferred to step 2/3 (discovery), where the types first need to cross the bridge.
- Any actual SOAP/UPnP code.
