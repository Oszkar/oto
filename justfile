# Common dev commands for the oto monorepo.
# Use `just <recipe>` from the repo root. The same recipes live in `Makefile`.
#
# Recipes use `[working-directory: '...']` instead of `cd ... && ...` so they
# work on every shell (cmd, bash, zsh, PowerShell 7+) without relying on
# shell-specific statement separators. PowerShell 7+ is required on Windows.

set windows-shell := ["pwsh.exe", "-NoLogo", "-NoProfile", "-Command"]

default:
    @just --list

# Regenerate FRB bindings from native/src/api.rs into app/lib/src/rust/, then
# run riverpod_generator over Dart sources.
gen: gen-rust gen-dart

[working-directory: 'app']
gen-rust: && gen-rust-fmt
    flutter_rust_bridge_codegen generate

# FRB formats its output with `rustfmt --edition 2018`; re-format with the
# workspace rustfmt (edition 2024, via native/rustfmt.toml) so the generated
# file satisfies `cargo fmt --check`. Mirrored in scripts/verify_generated.dart.
[working-directory: 'native']
gen-rust-fmt:
    rustfmt src/frb_generated.rs

[working-directory: 'app']
gen-dart:
    dart run build_runner build

gen-check:
    dart scripts/verify_generated.dart

# Single canonical gate — mirrors CI's read-only jobs (generated,
# rust fmt/clippy, flutter analyze, deny). Run this before pushing.
# Tests are separate (`just test`) so unrelated test work doesn't
# block the lint loop.
check: gen-check fmt clippy analyze deny

[working-directory: 'native']
fmt:
    cargo fmt --all --check

[working-directory: 'native']
fmt-fix:
    cargo fmt --all

[working-directory: 'native']
clippy:
    cargo clippy --workspace --all-targets -- -D warnings

[working-directory: 'app']
analyze:
    flutter analyze

# Tests.
test: test-rust test-dart

[working-directory: 'native']
test-rust:
    cargo nextest run --workspace

[working-directory: 'app']
test-dart:
    flutter test

# Bridge smoke: boots the app on a connected device / desktop so the FRB
# cdylib actually loads. Not part of `just test` (or CI) because Flutter's
# `integration_test` needs a display target — neither ubuntu-latest nor
# the build.yml matrix are wired up for that. Run manually against
# Windows / Android when validating a release.
[working-directory: 'app']
test-integration:
    flutter test integration_test/

# Supply-chain check (runs cargo deny against the workspace).
[working-directory: 'native']
deny:
    cargo deny check

install-hooks:
    lefthook install

# Run the Flutter app on the host desktop (the documented manual-verify
# loop, see AGENTS.md). Needs Sonos devices on the LAN to do anything
# useful; Flutter picks the local device or prompts when several exist.
[working-directory: 'app']
dev:
    flutter run

# Run the fixture-driven design-system showcase (screens/states gallery, no
# LAN/Sonos needed). A live design board - hot reload to iterate on UI. See
# docs/design-system/README.md.
[working-directory: 'app']
showcase:
    flutter run -t lib/showcase/main.dart

# Debug builds.
[working-directory: 'app']
build-apk:
    flutter build apk --debug

[working-directory: 'app']
build-win:
    flutter build windows --debug

# Pull Flutter dependencies and verify Cargo can resolve the workspace.
bootstrap: bootstrap-app bootstrap-native

[working-directory: 'app']
bootstrap-app:
    flutter pub get

[working-directory: 'native']
bootstrap-native:
    cargo check --workspace

# Wipe build artifacts.
clean: clean-app clean-native

[working-directory: 'app']
clean-app:
    flutter clean

[working-directory: 'native']
clean-native:
    cargo clean
