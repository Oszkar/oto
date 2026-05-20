# FRB discover command — design

**Date:** 2026-05-15 **Status:** Decided. Pins the v0.1 FRB discovery surface before implementation. Folded into `docs/ARCHITECTURE.md` (living design); this doc is the point-in-time decision record (the A/B/C rationale). **Scope:** v0.1 milestone — *identity-only* LAN discovery, proven end-to-end through the Rust↔Dart bridge without the real UI.

## Context

v0.1 (README milestone ladder) = Foundation + LAN discovery. The remaining v0.1 work is the `Wire` trait, `oto-wire` SSDP, `oto-app`, `oto-mock`, and the FRB surface. This doc pins the **FRB discover command** — a §7 high-impact boundary that needs an ARCHITECTURE.md update before code.

Hard constraints feeding the decision:

- `sonos-sdk` is **sync-first and blocking**; no async API to `await`.
- `SonosSystem::new()` blocks ~3–4.6 s and its built-in SSDP is broken on multi-NIC hosts — see [discovery spike findings](2026-05-15-discovery-spike-findings.md). `oto-wire` therefore runs its own SSDP and builds the system via `SonosSystem::from_discovered_devices` (behind `sonos-sdk`'s `test-support` feature; pin `=0.5.2`).
- Discovery must be a **deferred warm-up command, not on the `#[frb(init)]` path** — a startup freeze is unacceptable.
- Identity-only: post-discovery, `volume`/`mute`/`playback_state.get()` return `None`; `id`/`name`/`ip`/`model`/topology are available at once. v0.1 surfaces only the latter.
- Project convention: commands sync returning `Result`, events as a `Stream`. Discovery is the documented exception (it blocks).

## Decision

**Approach A — async command returning a snapshot `Future`.**

```rust
// native/src/api.rs — default (non-sync) FRB fn → Dart Future
pub fn discover() -> Result<Topology, DiscoveryError>
```

FRB runs the blocking pipeline on its own worker executor, off the Dart UI isolate. Dart consumes it via a Riverpod `FutureProvider`; the resulting `AsyncValue` *is* the loading / error / data state machine the spike says we need. Retry = `ref.invalidate(...)`.

### Why A (vs. B / C)

| | A — async command → Future | B — sync kick-off + event Stream | C — sync kick-off + sync poll |
|---|---|---|---|
| Off-UI threading | FRB executor hosts the blocking call; we spawn nothing | We hand-roll a `std::thread` + `StreamSink` + teardown | We hand-roll a thread + shared state + a poll API |
| Dart consumption | `FutureProvider` → `AsyncValue` (free) | `StreamProvider` + manual reduction; pre-subscribe race | Hand-rolled polled notifier + `Timer` |
| Fit to `sonos-sdk` | Mirrors it: one-shot blocking snapshot read | Forces a stream onto a one-shot; event path is a *different* primitive (`ChangeIterator`) | Same as B plus a poll layer |
| ARCHITECTURE delta | One command; event surface deferred to v0.3 | Introduces the whole event/concurrency surface in the *discovery* milestone | As B, worse |
| Risk | **Low** — conventional only; doc already carves the exception | **Medium** — bakes an event shape while the v0.3 `ChangeIterator`/ZoneGroupTopology model is still unvalidated (spike Q1) | **Low tech, high throwaway** — near-certain rip-out in v0.3 |

`sonos-sdk`'s sync-first, *one-shot-discovery / separate-iterator-events* shape pushes hardest toward A and actively erodes B's only real advantage (pre-building event infra): a v0.1 discovery `StreamSink` would not transfer much to a v0.3 `ChangeIterator` pump, and that pump's shape depends on behavior the spike has **not** validated (topology change events — open question #1). Building the event boundary now would likely mean building it twice and re-running a §7 sign-off. C is dominated by B.

**Rejected:** B (premature event surface on unvalidated behavior); C (polling, worst ergonomics, dominated by B).

## Surface

### Command

```rust
/// Deferred warm-up. Runs oto-wire LAN discovery (own multi-interface
/// SSDP → device descriptions → SonosSystem::from_discovered_devices)
/// and returns an identity-only snapshot. Blocking ~3–5 s; FRB runs it
/// off the UI isolate. NOT on the #[frb(init)] path. Idempotent:
/// success replaces the SonosSystem oto-app holds; failure leaves any
/// prior system intact.
pub fn discover() -> Result<Topology, DiscoveryError>
```

### Return DTOs — identity-only, deliberately *not* `oto_core::Speaker/Group`

```rust
pub struct Topology {
    pub speakers: Vec<DiscoveredSpeaker>,
    pub groups: Vec<DiscoveredGroup>,
}
pub struct DiscoveredSpeaker {
    pub id: String,             // SpeakerId
    pub room_name: String,
    pub model: Option<String>,
    pub ip: String,             // IpAddr rendered to String for FRB
}
pub struct DiscoveredGroup {
    pub id: String,             // GroupId
    pub coordinator: String,    // SpeakerId
    pub members: Vec<String>,   // SpeakerId; coordinator at members[0]
}
```

`oto_core::Speaker` carries `volume`/`muted`; `Group` carries `transport`. The spike proved these are `None`/default immediately post-discovery. Exposing them at v0.1 would lie to Dart about data we don't have. A lean DTO structurally enforces "identity-only" and lets v0.2 add fields/commands without reshaping. `oto-core` stays the internal lingua franca; `oto-app` maps `oto_core` → these FRB DTOs.

### Error enum

```rust
pub enum DiscoveryError {
    Network(String),   // no usable IPv4 interface / SSDP send failed
    NoDevicesFound,    // SSDP ok, zero Sonos — distinct so UI can say
                       //   "no Sonos on this network" vs. "discovery failed"
    Sdk(String),       // device-description fetch/parse or
                       //   SonosSystem construction failed
}
```

All variants are **retryable** (AGENTS.md §3 — discovery failures are not fatal). Dart maps to `AsyncError`; retry = `ref.invalidate(...)`.

`oto-app` is the single mapping layer: it maps `Wire`'s `WireError` → `DiscoveryError` and `oto-core`'s `DiscoverySnapshot` → the FRB `Topology` DTO (which is a 1:1 mirror of `DiscoverySnapshot` with FRB-friendly field types, e.g. `IpAddr` rendered to `String`). The FRB layer (`native/src/api.rs`) stays glue-only — no business logic, no error classification.

### `Wire` trait — minimal, identity-honest (decision B)

One method; the internal snapshot is a **lean identity type in `oto-core`**, not `Speaker`/`Group` with defaulted fields:

```rust
// oto-core — new identity types (v0.2 grows Speaker *around* these)
pub struct SpeakerIdentity { pub id: SpeakerId, pub room_name: String,
                             pub model: Option<String>, pub ip: IpAddr }
pub struct GroupIdentity   { pub id: GroupId, pub coordinator: SpeakerId,
                             pub members: Vec<SpeakerId> }
pub struct DiscoverySnapshot { pub speakers: Vec<SpeakerIdentity>,
                               pub groups: Vec<GroupIdentity> }

// the Wire seam — one method for v0.1
pub trait Wire {
    fn discover(&self) -> Result<DiscoverySnapshot, WireError>;
}
```

Rationale: "identity-only" is then true at *every* layer, not just at the bridge. v0.2 makes `Speaker` embed `SpeakerIdentity` rather than retrofitting. `oto-mock` implements `Wire` with deterministic fixtures so the end-to-end v0.1 test runs without a LAN.

> Touches two §7 boundaries (the `Wire` trait *and* new `oto-core` types). Both are signed off here.

### Lifecycle / state ownership

`oto-app` owns a process-global holding the constructed `SonosSystem` (so v0.2 playback can act on it). `discover()`:

- builds a fresh system via `oto-wire`;
- on success: stores it (replace-on-success), returns the `Topology` snapshot;
- on failure: leaves any prior system intact, returns `Err`.

No background threads in v0.1 — continuous events are a separate `ChangeIterator`-backed `Stream`, **deferred to v0.3**. `init_app` stays FRB-setup-only.

### Riverpod

A `FutureProvider` (`app/lib/src/state/`) calling `discover()`; `AsyncValue` drives loading / error / data; pull-to-retry via `ref.invalidate`.

## Validation bar (v0.1 "done")

A headless Dart/integration test drives `discover()` against `oto-mock` and asserts the returned `Topology` — proving the bar (README:143–145) without the designed UI.

## Open items (verify at implementation-plan time — do not guess)

1. **Exact `Device` construction API under `sonos-sdk`'s `test-support` feature in `=0.5.2`** — whether the crate exposes a `Device` parse/from-URL path or `oto-wire` fetches + parses the device description XML itself. context7 does not index this crate (only the out-of-scope Sonos *cloud* platform); verify against the crate source when writing the implementation plan. Affects `oto-wire` internals only — **not** the FRB surface above.
2. **`ip: String` rendering** — confirm `IpAddr → String` (e.g. `to_string()`) is the shape Dart wants, vs. a structured type. Low impact; default to `to_string()` unless the plan finds a reason.

## Out of scope (correctly deferred)

- ZoneGroupTopology *change* events (ARCHITECTURE open Q1) → v0.3.
- `volume`/`mute`/`playback_state` and playback commands → v0.2.
- The continuous event `Stream` and its pump thread → v0.3.
- Bonded/satellite/asleep device-count discrepancy (spike "new open item") → known-incomplete, acceptable for v0.1.

## Related docs

- [discovery spike findings](2026-05-15-discovery-spike-findings.md)
- `docs/plans/2026-05-15-oto-core-domain-types-design.md`
- `docs/ARCHITECTURE.md` — living design (updated alongside this doc)

---

## Addendum — hardware verification (2026-05-16)

The body above is the point-in-time decision record (kept as-decided). Task-8 verification on a real multi-NIC Sonos LAN (Beam + One + a SYMFONISK Bookshelf stereo pair, 4 device descriptions) changed two implementation decisions. The FRB **surface** (Approach A, the DTOs, the error enum, the minimal `Wire` trait, non-sync `discover()`) is unchanged and validated.

**1. D3 reversed: chunked HTTP → `ureq`.** The body assumed a raw `TcpStream` GET would fetch device descriptions. Hardware: Sonos's embedded server replies `HTTP/1.1` `Transfer-Encoding: chunked` (no `Content-Length`, many tiny chunks) even to an HTTP/1.0 request, so the raw GET handed `quick_xml` chunk-framed bytes and every parse failed. Fix (user-approved): use `ureq` — already a **locked transitive dep** (`oto-wire → sonos-sdk → sonos-sdk-soap-client → ureq 2.12.1`), so this adds **no new supply-chain**; it handles chunked + UTF-8. The caller's `timeout` is applied via `AgentBuilder::timeout_connect` + `timeout` so connect is bounded too. (Resolves **open item #1**: oto-wire fetches + parses the XML itself via `sonos_discovery::DeviceDescription::from_xml`; `ureq` is the fetcher. Open item #2 resolved: `IpAddr::to_string()`.)

**2. v0.1 snapshot built from own devices, NOT sonos-sdk topology.** The body (Context, Command doc-comment, Lifecycle) said `oto-wire` constructs the system via `SonosSystem::from_discovered_devices` and the snapshot comes from it. Hardware proved this path **lazy / lossy / non-deterministic**: fed all 4 correctly-discovered devices, `system.speakers()` returned only 1 (Kitchen) and flapped 0↔1 across runs — the documented ZoneGroupTopology weak spot (ARCHITECTURE Open Q1). Decision (user-approved, Option A): since v0.1 is **identity-only** and `oto-wire`'s own `to_devices()` already yields complete, deterministic per-device identity, `SonosWire::discover()` now maps that `Vec<sonos_discovery::Device>` **directly** to `DiscoverySnapshot` (`to_snapshot()`), with **no `SonosSystem` / `from_discovered_devices` in the v0.1 path**. Consequences:

- **Groups = group-of-one** for v0.1 (`{speaker_id}:0`, coordinator = members = the speaker). Real ZoneGroupTopology (multi-room groups, bonded stereo pairs / HT surrounds, coordinator/topology-change events) is **v0.3** (ARCHITECTURE Open Q1 + Q4).
- **Known v0.1 limitation:** bonded surrounds (the SYMFONISK pair) are listed as standalone players. Accepted and documented (README, ARCHITECTURE Q4).
- **Net positive:** the v0.1 happy path is now pure and **deterministically unit-testable with no LAN** (the `to_snapshot` tests), removing the dependency on sonos-sdk's lazy topology for the v0.1 acceptance bar.
- `oto-app` still holds the active `Wire` (replace-on-success); `SonosSystem` ownership returns in **v0.2** (playback), where the `from_discovered_devices`/topology path is re-evaluated.
- `test-support` is still required (gates `sonos_discovery::{Device, DeviceDescription}`); `=0.5.2` pin stands.

The "Lifecycle / state ownership" and Command doc-comment text above (which reference `SonosSystem`) are **superseded for v0.1** by this addendum; they describe the v0.2+ target.
