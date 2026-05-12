# Common dev commands for the oto monorepo.
# Use `just <recipe>` from the repo root. The same recipes live in `Makefile`.

set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-Command"]

default:
    @just --list

# Regenerate FRB bindings from native/src/api.rs into app/lib/src/rust/, then
# run riverpod_generator over Dart sources.
gen: gen-rust gen-dart

gen-rust:
    cd app && flutter_rust_bridge_codegen generate

gen-dart:
    cd app && dart run build_runner build

gen-check:
    dart scripts/verify_generated.dart

# Fast feedback loop: format + lint everything.
check: fmt clippy analyze

fmt:
    cd native && cargo fmt --all --check

fmt-fix:
    cd native && cargo fmt --all

clippy:
    cd native && cargo clippy --workspace --all-targets -- -D warnings

analyze:
    cd app && flutter analyze

# Tests.
test: test-rust test-dart

test-rust:
    cd native && cargo nextest run --workspace

test-dart:
    cd app && flutter test

# Supply-chain check (runs cargo deny against the workspace).
deny:
    cd native && cargo deny check

install-hooks:
    lefthook install

# Debug builds.
build-apk:
    cd app && flutter build apk --debug

build-win:
    cd app && flutter build windows --debug

# Pull Flutter dependencies and verify Cargo can resolve the workspace.
bootstrap:
    cd app && flutter pub get
    cd native && cargo check --workspace

# Wipe build artifacts.
clean:
    cd app && flutter clean
    cd native && cargo clean
