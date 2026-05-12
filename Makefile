# Mirror of justfile. Prefer `just` when available; this exists so a fresh
# clone can run `make check` without installing anything extra.

.PHONY: default gen check fmt fmt-fix clippy analyze test test-rust test-dart \
        deny build-apk build-win bootstrap clean

default:
	@echo "Recipes: gen check fmt fmt-fix clippy analyze test test-rust test-dart deny build-apk build-win bootstrap clean"

gen:
	cd app && flutter_rust_bridge_codegen generate

check: fmt clippy analyze

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

deny:
	cd native && cargo deny check

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
