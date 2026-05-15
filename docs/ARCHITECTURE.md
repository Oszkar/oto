# Architecture

How oto is structured: a Flutter UI over a Rust core, with all Sonos
networking delegated to [`tatimblin/sonos-sdk`][sdk].

> **Status — this is the target design, not current code.** Implemented
> today: `oto-core` (domain types) and the `oto-wire` skeleton (a
> `sonos-sdk` dependency pin + link check). Not yet built: the `Wire`
> trait, `oto-app`, the `oto-mock` fixtures, and the FRB command/event
> surface. Inline notes and the Crates table mark what exists vs. what's
> planned. Prose describes the intended design; it is not a claim that
> the code exists today.

## Layers

```mermaid
flowchart TD
    UI["Flutter UI<br/>ConsumerWidgets"]
    RP["Riverpod providers<br/>app/lib/src/state/"]
    FRB["FRB bridge<br/>native/src/api.rs"]
    APP["oto-app<br/>translation + lifecycle"]
    CORE["oto-core<br/>domain types"]
    WIRE{{"Wire trait"}}
    WIREIMPL["oto-wire<br/>sonos-sdk adapter"]
    MOCK["oto-mock<br/>deterministic fakes"]
    SDK["sonos-sdk<br/>SSDP · SOAP · GENA"]
    NET(("Sonos speakers<br/>on the LAN"))

    UI --> RP
    RP -->|sync commands| FRB
    FRB -->|"Stream&lt;Event&gt;"| RP
    FRB --> APP
    APP --> CORE
    APP --> WIRE
    WIRE -.impl.-> WIREIMPL
    WIRE -.impl.-> MOCK
    WIREIMPL --> SDK
    SDK <--> NET
```

## Crates

| Crate | Path | Responsibility |
|---|---|---|
| `oto_native` | `native/` | FRB cdylib. Thin shim — exposes commands and event streams to Dart, delegates everything else. |
| `oto-app` | (not yet created) | Owns the `SonosSystem` instance and the background threads that pump events. Translates `sonos_sdk` types ↔ `oto_core` types. Routes commands. |
| `oto-core` | `native/crates/core` | Pure domain types (`Speaker`, `Group`, `TransportState`, `Track`, `Volume`, identifiers). No networking, no async, no third-party deps. |
| `oto-wire` | `native/crates/wire` | _Planned:_ production `Wire` implementation backed by `sonos-sdk`. _Today:_ skeleton — dependency pin + link check, no adapter or trait yet. |
| `oto-mock` | `native/crates/mock` | _Planned:_ `Wire` implementation with deterministic in-memory fixtures, for tests without a LAN. _Today:_ placeholder stub only. |

The Dart side is Flutter + Riverpod 3 (codegen). Providers live in
`app/lib/src/state/`; FRB-generated bindings in `app/lib/src/rust/`.

## State ownership

State lives in Rust, not Dart. `sonos-sdk`'s `StateManager` caches
per-speaker and per-group properties and emits `ChangeEvent`s on change.
`oto-app` holds the `SonosSystem`; Dart Riverpod providers subscribe to
event streams and hold projections for rendering, not source data.

Consequences:

- State survives Flutter hot reload / UI restart.
- A non-Flutter client (e.g. a CLI) could reuse the same core unchanged.
- State mutations happen where network events are handled (Rust), avoiding
  cross-FFI consistency bugs.

## Command and event flow

Commands are synchronous Dart → Rust calls returning `Result`. Events are
an asynchronous Rust → Dart stream. The two are independent: a command's
success/failure is separate from the state change it eventually causes.

```mermaid
sequenceDiagram
    participant U as Flutter UI
    participant B as FRB bridge
    participant A as oto-app
    participant S as sonos-sdk
    participant K as Sonos speaker

    Note over U,K: Command — sync, Dart to Rust
    U->>B: play groupId
    B->>A: route command
    A->>S: Group play
    S->>K: UPnP SOAP request
    S-->>A: result
    A-->>B: Ok or Error
    B-->>U: result

    Note over U,K: Event — async, Rust to Dart
    K->>S: GENA NOTIFY LastChange
    S->>S: decode, StateManager, ChangeEvent
    A->>S: ChangeIterator recv on bg thread
    A->>A: map ChangeEvent to domain event
    A-->>B: push onto Stream
    B-->>U: Stream yields, providers rebuild
```

## Concurrency model

`sonos-sdk` is sync-first; no async runtime is required at the bridge.

- Commands: synchronous FRB calls into synchronous `sonos-sdk` methods.
- Events: `sonos-sdk`'s `ChangeIterator::recv()` blocks. Each event stream
  exposed to Dart is pumped by a dedicated OS thread that reads the
  iterator and pushes onto an FRB `Stream`.

No `tokio` in oto's own code. (`sonos-sdk` uses async internally; that is
encapsulated and does not surface at the `Wire` boundary.)

## The `Wire` seam

_Planned; none of the `Wire` trait, `oto-app`, or the impls below exist
yet — see the Status note above._

`oto-app` will depend on a `Wire` trait rather than on `sonos-sdk`
directly. Production will use `oto-wire` (a thin shim over `sonos-sdk`);
tests will use `oto-mock` (deterministic fixtures). This keeps
integration tests runnable without a Sonos device on the network and
isolates any future library swap to a single crate.

## Scope

- **Targets:** Android (API 35+, 64-bit) and Windows. Other platforms
  compile but are untested.
- **Local-first:** LAN-only. No cloud, no account, no Sonos HTTP API.
- **No persistence** beyond what `sonos-sdk` caches in memory. No on-disk
  state or config yet.

## Open questions

To validate when the wire layer is fleshed out (the `oto-wire` adapter and
the discovery/event steps):

1. **ZoneGroupTopology coverage.** Grouping/topology event handling is the
   historical weak spot in Sonos libraries. Confirm `sonos-sdk` decodes
   topology changes (group form/break, coordinator change) reliably. If
   not, this is the first candidate for an upstream contribution.
2. **Discovery blocking on startup.** `SonosSystem::new()` performs
   discovery. If it blocks for a timeout, it must not run inside FRB's
   `init_app` (which would freeze UI startup). Likely mitigation: construct
   `SonosSystem` from a "warm up" command issued after the UI mounts.
3. **Thread count.** One OS thread per exposed event stream (blocking
   `ChangeIterator`). Cheap, but confirm the stream granularity so the
   thread count stays bounded (e.g. one multiplexed event stream rather
   than one per speaker).

## Related docs

- `docs/plans/2026-05-15-oto-core-domain-types-design.md` — rationale for
  the `oto-core` type shapes (newtypes, transport-on-`Group`, etc.).

[sdk]: https://github.com/tatimblin/sonos-sdk
