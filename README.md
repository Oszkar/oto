<p align="center">
  <img src="docs/design-system/brand/oto-mark-512.png" alt="oto logo" width="128" height="128" />
</p>

<h1 align="center">oto</h1>

<p align="center">
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT" />
  </a>
  <a href="https://github.com/Oszkar/oto/actions/workflows/ci.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/Oszkar/oto/ci.yml?branch=main&label=CI" alt="CI" />
  </a>
  <a href="https://github.com/Oszkar/oto/releases/latest">
    <img src="https://img.shields.io/github/v/release/Oszkar/oto?label=release" alt="Release" />
  </a>
</p>

A fast, local-first Sonos controller for Windows and Android. Flutter UI over a Rust core, connected by generated `flutter_rust_bridge` bindings. Sonos discovery, control, and live events run locally in Rust.

oto is a side project, primarily built with agentic engineering methods. The name means "sound" in Japanese and is a palindrome, like Sonos.

## Features

- Discover Sonos rooms on your LAN, including hosts with multiple network interfaces.
- Play, pause, skip tracks, and control room or group volume and mute.
- Group and ungroup rooms, with live topology and playback updates.
- View Now Playing metadata and track progress.
- Use phone, tablet, and desktop layouts with light/dark themes and local preferences.

## Scope

Windows and Android 15+ (API 35), with 64-bit Android ABIs only. Other platform folders are scaffolding, not supported or routinely validated targets.

Local control only: no Sonos account, cloud API, or multi-household support. Shuffle, repeat, seek, queue editing, and EQ controls are not implemented. oto is not affiliated with Sonos.

## Development setup

- Flutter version from [`.fvmrc`](.fvmrc).
- Rust toolchain from [`rust-toolchain.toml`](rust-toolchain.toml), installed by rustup.
- [`just`](https://github.com/casey/just) (preferred), or `make` for the mirrored recipes.
- Windows: Visual Studio 2022 with the "Desktop development with C++" workload and PowerShell 7+ for `just`.
- Android: Java 21, Android SDK, and the NDK selected by Flutter. See [Android cross-builds](CONTRIBUTING.md#android-cross-builds).

Install Cargo tools, then resolve app and workspace dependencies:

```bash
cargo install flutter_rust_bridge_codegen --version 2.12.0 --locked
cargo install cargo-ndk cargo-nextest cargo-deny --locked
just bootstrap
```

Optional Git hooks: install [Lefthook](https://github.com/evilmartians/lefthook), then run `just install-hooks`.

## Common commands

Run from the repository root:

```bash
just gen               # regenerate committed FRB + Riverpod bindings
just check             # generated freshness, Rust fmt/clippy, Flutter analyze, cargo deny
just test              # Rust + Flutter unit/widget tests
just test-integration  # Windows desktop, real FRB bridge with MockWire
just dev               # run the app, using speakers on the LAN
just showcase          # fixture-driven UI gallery, no speakers needed
just build-apk         # debug Android APK
just build-win         # debug Windows desktop
```

Regenerate after changing the bridge API or an `@riverpod` provider. The [contributor guide](CONTRIBUTING.md) covers validation, version pins, hooks, and PRs.

## Local network setup

The app and speakers must be able to reach each other on the LAN. Guest-network isolation or multicast filtering can prevent discovery.

Allow oto's outbound SSDP multicast to UDP port 1900 and the replies to its per-interface ephemeral UDP sockets. SOAP uses TCP port 1400 on the speakers; GENA notifications require speakers to reach the app's callback listener (SDK range 3400-3500). Prefer an application-scoped firewall rule on the private LAN.

On Android, oto acquires a Wi-Fi `MulticastLock` around discovery. GENA notifications use unicast TCP. Protocol details and discovery limitations are in [Sonos notes](docs/sonos-notes.md#ssdp-discovery).

## Repository guide

| Location | Purpose |
| --- | --- |
| `app/` | Flutter UI, Riverpod state, generated Dart bridge |
| `app/rust_builder/` | Cargokit plugin that builds the Rust library for Flutter |
| `native/src/` | FRB API, DTO mapping, event consumer, generated Rust glue |
| `native/crates/{core,wire,mock,app}/` | Domain, Sonos integration, test wire, runtime ownership |
| [Architecture](docs/ARCHITECTURE.md) | Current layers, state ownership, command and event flows |
| [Sonos notes](docs/sonos-notes.md) | Protocol constraints and SDK integration pitfalls |
| [Design system](docs/design-system/README.md) | Canonical tokens, showcase, brand assets |
| [Local patches](LOCAL_PATCHES.md) | Vendored changes and upgrade instructions |
| [Agent contract](AGENTS.md) | Engineering boundaries and required checks |

## CI and releases

[CI](.github/workflows/ci.yml) checks generated source, Rust, Flutter, dependencies, and Android Rust cross-compilation on PRs. The [build workflow](.github/workflows/build.yml) builds a debug APK on `main`, relevant PRs, and manual dispatch. The manually dispatched [integration gate](.github/workflows/integration-gate.yml) runs the full FRB integration tests on Windows. PR-title linting and Dependabot auto-merge are described in [Contributing](CONTRIBUTING.md).

The app is pre-1.0; behavior and API compatibility may change between releases. See the [roadmap](docs/ROADMAP.md) for milestone status and forward scope, the [changelog](CHANGELOG.md) for release history, and [Releasing](RELEASING.md) for the release procedure. Signed distribution packages are still planned.
