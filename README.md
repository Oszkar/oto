# oto

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) [![CI](https://img.shields.io/github/actions/workflow/status/Oszkar/oto/ci.yml?branch=main&label=CI)](https://github.com/Oszkar/oto/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/Oszkar/oto?label=release)](https://github.com/Oszkar/oto/releases/latest)

A fast, local-first Sonos controller for Windows and Android, without the bloat of the official app. Flutter UI on top of a Rust core, bridged with [`flutter_rust_bridge`][frb] v2. Discovery and SOAP control stay in Rust via the [`sonos-api`](https://crates.io/crates/sonos-api) crate (part of the [`tatimblin/sonos-sdk`](https://github.com/tatimblin/sonos-sdk) family) and oto's own multi-NIC SSDP; v0.4 live events build on the same SDK family's reactive state layer. The UI talks to Rust only through generated FRB bindings.

> note: `oto` is a working name for now. It means `sound` in Japanese and it is a palindrome, just like Sonos 

## Scope

- **Platforms:** Android and Windows at the moment. macOS/iOS/Web scaffolding compiles, kept as a future potential target.
- **Android floor:** `minSdk = 35` (Android 15, released Q4 2024). Sonos buyers tend to be on recent hardware and the scope reduction simplifies testing. Practical implication: APKs ship arm64-v8a + x86_64 only — see [LOCAL_PATCHES.md](LOCAL_PATCHES.md) for the cargokit patch that enforces this.

## Layout

```text
oto/
├─ app/                  # Flutter app (android + windows targets first)
│  ├─ lib/               # Dart source
│  ├─ lib/src/rust/      # FRB-generated Dart bindings (committed, regenerated)
│  ├─ rust_builder/      # Cargokit Flutter plugin (builds the native lib per platform)
│  ├─ android/, windows/, ios/, macos/, web/
│  └─ flutter_rust_bridge.yaml
├─ native/               # Rust workspace
│  ├─ Cargo.toml         # workspace root + FRB-exposed cdylib package (oto_native)
│  ├─ src/api.rs         # FRB-exposed API surface — keep small, delegate inward
│  ├─ src/map.rs         # domain → FRB-DTO map (off the bridged surface, so testable)
│  ├─ src/lib.rs         # mounts api + map + frb_generated
│  ├─ crates/core/       # oto-core: pure domain types + Wire trait
│  ├─ crates/wire/       # oto-wire: production Wire — own SSDP + direct sonos-api SOAP + event subscriptions
│  ├─ crates/mock/       # oto-mock: deterministic fake speakers for tests
│  ├─ crates/app/        # oto-app: owns runtime state, routes discover + playback commands
│  └─ rustfmt.toml
├─ docs/                 # ARCHITECTURE.md + design docs
├─ scripts/
├─ .github/workflows/
├─ rust-toolchain.toml
├─ Makefile
└─ justfile
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the system design — layers, crate responsibilities, state ownership, and the command/event flow.

The Flutter plugin `app/rust_builder/` is the [Cargokit][cargokit] integration shim that compiles `native/` into the right shared library for each platform during a normal `flutter build`. Its CMake / Gradle / Podspec files point at `../../../native` (or deeper, on Windows where the symlink chain is longer); if you move `native/` or `rust_builder/`, update those paths.

We carry one **local patch** against vendored Cargokit to drop 32-bit Android ABIs from the Rust build target list. See [LOCAL_PATCHES.md](LOCAL_PATCHES.md) for the diff and re-apply procedure if you ever sync Cargokit from upstream.

[frb]: https://github.com/fzyzcjy/flutter_rust_bridge
[cargokit]: https://github.com/irondash/cargokit

## Prerequisites

- Flutter stable (currently 3.38.x)
- Rust 1.94+ via `rust-toolchain.toml` (auto-installed by rustup)
- Cargo extensions: `flutter_rust_bridge_codegen`, `cargo-ndk`, `cargo-nextest`, `cargo-deny`
- Optional: [`lefthook`][lefthook] for local Git hooks
- Android: Android Studio + SDK + NDK (NDK version pinned by Flutter)
- Windows: Visual Studio 2022 with the "Desktop development with C++" workload, plus PowerShell 7+ (required by `just`; `winget install Microsoft.PowerShell`)

Install once:

```bash
cargo install flutter_rust_bridge_codegen --version 2.12.0 --locked
cargo install cargo-ndk cargo-nextest cargo-deny --locked
```

Install Lefthook separately if you want the pre-commit generated-source check:

```bash
brew install lefthook      # macOS/Linux
winget install evilmartians.lefthook  # Windows
just install-hooks
```

`just` runs dev recipes on demand (`gen`, `check`, `test`, `build-*`, `install-hooks`). `lefthook` is the optional git-hook runner that, once installed, runs **only one** check automatically before every commit: `scripts/verify_generated.dart` (catches stale generated source). CI runs the same check server-side — Lefthook just shortens the local feedback loop.

## Common commands

The same recipes are mirrored in both `Makefile` and `justfile`. Pick whichever runner you have. With `just`:

```bash
just gen          # FRB bindings + riverpod_generator (re-run after editing native/src/api.rs or any @riverpod-annotated Dart)
just gen-check    # regenerate generated source and fail if it differs from git
just check        # gen-check + cargo fmt + clippy + flutter analyze + cargo deny
just test         # cargo nextest + flutter test
just build-apk    # debug Android APK
just build-win    # debug Windows desktop
```

`just gen` runs in two stages:

1. `flutter_rust_bridge_codegen generate` — reads `native/src/api.rs` and writes Dart bindings into `app/lib/src/rust/` plus Rust glue into `native/src/frb_generated*.rs`.
2. `dart run build_runner build` — runs `riverpod_generator` over Dart sources and emits `*.g.dart` files alongside their inputs.

These generated source files are committed. That keeps a fresh clone usable in IDEs and on Windows/macOS/Linux without requiring every contributor to run codegen before `flutter analyze`, `flutter test`, or `cargo check`. CI and the optional Lefthook pre-commit hook run `scripts/verify_generated.dart`, which regenerates them and fails if the checked-in output is stale.

## CI

Two workflows under `.github/workflows/`:

- `ci.yml` — verifies generated source freshness, then runs lint + tests for Flutter and Rust on every PR. Jobs are split so they run in parallel and can be re-run independently.
- `build.yml` — debug-builds the Android APK on pushes to `main` to catch toolchain rot. No Windows job — fluctuating runner minutes aren't worth it for a hobby project; dev machines catch Windows issues.

## Architecture

System design — layers, crate responsibilities, state ownership, concurrency model, and the command/event flow — lives in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Releases

Pre-1.0 (`0.y.z`) — surface and behavior may change between any releases. Versioning and the release process: [RELEASING.md](RELEASING.md); notable changes: [CHANGELOG.md](CHANGELOG.md).

### Milestones

Each pre-1.0 minor is one capability layer, proven end-to-end through the Rust↔Dart bridge and verifiable without the real UI. `v1.0` is the bounded, externally-tested end state; after it, maintenance only.

| Version | Capability |
|---|---|
| v0.1 ✓ | Foundation + LAN **discovery**. Domain types, `Wire` trait, `oto-app`, `oto-wire` SSDP, FRB surface, mock impl. |
| v0.2 ✓ | **Playback control** — play/pause/next/prev, volume, mute, one-shot state read. |
| v0.3 ✓ | **Grouping** — real ZoneGroupTopology: multi-room groups, coordinator election, bonded satellites folded. Reads one-shot (no event streams yet). |
| v0.4 ✓ | **Live property events** — reactive state via GENA for volume / mute / transport / track. One multiplexed FRB `Stream<ChangeEventDto>`; `speaker_state` reads from an event-fed cache. Topology events deferred to v0.5. |
| v0.5 ✓ | **Hardening before UI** — topology change events, Android `MulticastLock`, model repopulate, in-band subscription-failure surfacing. Group form/break deferred to v0.5.1. |
| v0.6 | **UI** — the designed Flutter interface on the proven capability layers. |
| v1.0 | **Stable** — externally tested, packaged (signed Android, Windows). Maintenance-only thereafter. |

Released: `v0.1.0`, `v0.2.0`, `v0.3.0`, `v0.4.0`, and `v0.5.0`. Commands are non-sync Dart `Future`s (every command is a blocking SOAP round-trip); live property changes flow as a Dart `Stream` (v0.4), with topology-change events on the same stream (v0.5). Milestone status, forward plan, and known caveats: [docs/ROADMAP.md](docs/ROADMAP.md). System design: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Per-release detail: [CHANGELOG.md](CHANGELOG.md).

## Development notes

- State management on the Dart side is **Riverpod 3 with codegen**. Define providers under `app/lib/src/state/` using `@riverpod`; they're consumed via `ref.watch(...)` from `ConsumerWidget`s. The app is wrapped in a single `ProviderScope` in `main.dart`.
- Generated source (`app/lib/src/rust/`, `native/src/frb_generated*`, `**/*.g.dart`) is committed for contributor ergonomics. Regenerate it with `just gen` after changing `native/src/api.rs` or any `@riverpod` provider.
