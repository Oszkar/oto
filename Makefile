# Mirror of justfile. Prefer `just` when available; this exists so a fresh
# clone can run `make check` without installing anything extra.

.PHONY: default gen gen-rust gen-dart gen-check check fmt fmt-fix clippy analyze test \
        test-rust test-dart test-integration deny install-hooks dev showcase build-apk build-win bootstrap clean

default:
	@echo "Recipes: gen gen-check check fmt fmt-fix clippy analyze test test-rust test-dart test-integration deny install-hooks dev showcase build-apk build-win bootstrap clean"

gen: gen-rust gen-dart

# The trailing rustfmt re-formats FRB's output with the workspace rustfmt
# (edition 2024) - FRB pins `rustfmt --edition 2018` internally. Mirrored in
# the justfile and scripts/verify_generated.dart.
gen-rust:
	cd app && flutter_rust_bridge_codegen generate
	cd native && rustfmt src/frb_generated.rs

gen-dart:
	cd app && dart run build_runner build

gen-check:
	dart scripts/verify_generated.dart

check: gen-check fmt clippy analyze deny

fmt:
	cd native && cargo fmt --all --check

fmt-fix:
	cd native && cargo fmt --all

clippy:
	cd native && cargo clippy --workspace --all-targets -- -D warnings

analyze:
	cd app && flutter analyze

test: test-rust test-dart

test-rust:
	cd native && cargo nextest run --workspace

test-dart:
	cd app && flutter test

# Bridge smoke — see justfile for full rationale. Not part of `test`/CI.
test-integration:
	cd app && flutter test integration_test/

deny:
	cd native && cargo deny check

install-hooks:
	lefthook install

# Run the Flutter app on the host desktop - see justfile for full rationale.
dev:
	cd app && flutter run

# Fixture-driven design-system showcase (no LAN/Sonos) - see justfile.
showcase:
	cd app && flutter run -t lib/showcase/main.dart

build-apk:
	cd app && flutter build apk --debug

build-win:
	cd app && flutter build windows --debug

bootstrap:
	cd app && flutter pub get
	cd native && cargo check --workspace

clean:
	cd app && flutter clean
	cd native && cargo clean
