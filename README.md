# oto

A fast, local-first Sonos controller for Windows and Android. Flutter UI on top
of a Rust core, bridged with [`flutter_rust_bridge`][frb] v2. All discovery,
SOAP control, and event-subscription logic stays in Rust; the UI talks to it
only through generated FRB bindings.

> **Status:** scaffold only. No Sonos logic yet.

## Layout

```text
oto/
├─ app/                  # Flutter app (android + windows targets first)
│  ├─ lib/               # Dart source
│  ├─ lib/src/rust/      # FRB-generated Dart bindings (regenerated, gitignored)
│  ├─ rust_builder/      # Cargokit Flutter plugin (builds the native lib per platform)
│  ├─ android/, windows/, ios/, macos/, linux/, web/
│  └─ flutter_rust_bridge.yaml
├─ native/               # Rust workspace
│  ├─ Cargo.toml         # workspace root + FRB-exposed cdylib package (oto_native)
│  ├─ src/api.rs         # FRB-exposed API surface — keep small, delegate to oto-core
│  ├─ src/lib.rs         # mounts api + frb_generated
│  ├─ crates/core/       # oto-core: domain logic (discovery, SOAP, state, events)
│  ├─ crates/mock/       # oto-mock: deterministic fake speakers for tests
│  └─ rustfmt.toml
├─ scripts/
├─ .github/workflows/
├─ rust-toolchain.toml
├─ Makefile
└─ justfile
```

The Flutter plugin `app/rust_builder/` is the [Cargokit][cargokit] integration
shim that compiles `native/` into the right shared library for each platform
during a normal `flutter build`. Its CMake / Gradle / Podspec files point at
`../../../native` (or deeper, on Windows where the symlink chain is longer);
if you move `native/` or `rust_builder/`, update those paths.

[frb]: https://github.com/fzyzcjy/flutter_rust_bridge
[cargokit]: https://github.com/irondash/cargokit

## Prerequisites

- Flutter stable (currently 3.38.x)
- Rust 1.94+ via `rust-toolchain.toml` (auto-installed by rustup)
- Cargo extensions: `flutter_rust_bridge_codegen`, `cargo-ndk`, `cargo-nextest`,
  `cargo-deny`
- Android: Android Studio + SDK + NDK (NDK version pinned by Flutter)
- Windows: Visual Studio 2022 with the "Desktop development with C++" workload

Install once:

```bash
cargo install flutter_rust_bridge_codegen --version "^2" --locked
cargo install cargo-ndk cargo-nextest cargo-deny --locked
```

## Common commands

The same recipes are mirrored in both `Makefile` and `justfile`. Pick whichever
runner you have. With `just`:

```bash
just gen          # regenerate FRB bindings (run after changing native/src/api.rs)
just check        # cargo fmt + clippy + flutter analyze
just test         # cargo nextest + flutter test
just build-apk    # debug Android APK
just build-win    # debug Windows desktop
```

The first run of `just gen` populates `app/lib/src/rust/` and
`native/src/frb_generated*.rs`. Both directories are gitignored — they're a
build artifact of `native/src/api.rs`.

## CI

Two workflows under `.github/workflows/`:

- `ci.yml` — lint + tests for Flutter and Rust on every PR. Two jobs (Flutter,
  Rust) so they run in parallel and can be re-run independently.
- `build.yml` — debug-builds the Android APK on pushes to `main` to catch
  toolchain rot. No Windows job — fluctuating runner minutes aren't worth it
  for a hobby project; dev machines catch Windows issues.

## Architecture notes

- The Rust workspace is split into the FRB cdylib (`native/`, package
  `oto_native`) and two member crates under `native/crates/`. `oto_native`
  is intentionally a thin shim: every public FRB function in `src/api.rs`
  should delegate into `oto-core`. This keeps the bridge surface small and
  unit-testable in pure Rust.
- `oto-mock` exists so Flutter integration tests and future end-to-end LAN
  tests share the same fake speaker fixtures.
- Generated FRB bindings (`app/lib/src/rust/` and `native/src/frb_generated*`)
  are not committed; they regenerate from `native/src/api.rs` whenever you
  run `just gen` or `flutter_rust_bridge_codegen generate`.
