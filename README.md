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
│  ├─ lib/src/rust/      # FRB-generated Dart bindings (committed, regenerated)
│  ├─ rust_builder/      # Cargokit Flutter plugin (builds the native lib per platform)
│  ├─ android/, windows/, ios/, macos/, web/
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
- Optional: [`lefthook`][lefthook] for local Git hooks
- Android: Android Studio + SDK + NDK (NDK version pinned by Flutter)
- Windows: Visual Studio 2022 with the "Desktop development with C++" workload, plus PowerShell 7+ (required by `just`; `winget install Microsoft.PowerShell`)

Install once:

```bash
cargo install flutter_rust_bridge_codegen --version "^2" --locked
cargo install cargo-ndk cargo-nextest cargo-deny --locked
```

Install Lefthook separately if you want the pre-commit generated-source check:

```bash
brew install lefthook      # macOS/Linux
winget install evilmartians.lefthook  # Windows
just install-hooks
```

## Common commands

The same recipes are mirrored in both `Makefile` and `justfile`. Pick whichever
runner you have. With `just`:

```bash
just gen          # FRB bindings + riverpod_generator (re-run after editing native/src/api.rs or any @riverpod-annotated Dart)
just gen-check    # regenerate generated source and fail if it differs from git
just check        # cargo fmt + clippy + flutter analyze
just test         # cargo nextest + flutter test
just build-apk    # debug Android APK
just build-win    # debug Windows desktop
```

`just gen` runs in two stages:

1. `flutter_rust_bridge_codegen generate` — reads `native/src/api.rs` and
   writes Dart bindings into `app/lib/src/rust/` plus Rust glue into
   `native/src/frb_generated*.rs`.
2. `dart run build_runner build` — runs `riverpod_generator` over Dart
   sources and emits `*.g.dart` files alongside their inputs.

These generated source files are committed. That keeps a fresh clone usable in
IDEs and on Windows/macOS/Linux without requiring every contributor to run
codegen before `flutter analyze`, `flutter test`, or `cargo check`. CI and the
optional Lefthook pre-commit hook run `scripts/verify_generated.dart`, which
regenerates them and fails if the checked-in output is stale.

## CI

Two workflows under `.github/workflows/`:

- `ci.yml` — verifies generated source freshness, then runs lint + tests for
  Flutter and Rust on every PR. Jobs are split so they run in parallel and can
  be re-run independently.
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
- State management on the Dart side is **Riverpod 3 with codegen**. Define
  providers under `app/lib/src/state/` using `@riverpod`; they're consumed
  via `ref.watch(...)` from `ConsumerWidget`s. The app is wrapped in a single
  `ProviderScope` in `main.dart`.
- Generated source (`app/lib/src/rust/`, `native/src/frb_generated*`,
  `**/*.g.dart`) is committed for contributor ergonomics. Regenerate it with
  `just gen` after changing `native/src/api.rs` or any `@riverpod` provider.
