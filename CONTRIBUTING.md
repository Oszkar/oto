# Contributing to oto

Short doc focused on the non-obvious bits. For setup/commands, see [README.md](README.md).

## Development workflow

The repo uses `just` (preferred) or `make`. Common loop:

```bash
just gen        # regenerate FRB + Riverpod source after editing native/src/api.rs
                # or any @riverpod-annotated Dart
just check      # gen-check + cargo fmt + clippy + flutter analyze + cargo deny
just test       # cargo nextest + flutter test
```

Generated source (`app/lib/src/rust/`, `native/src/frb_generated*`, `**/*.g.dart`) is committed. Always run `just gen` before committing changes to inputs. The Lefthook hooks (`just install-hooks`) mirror CI locally: pre-commit catches stale generated source and rustfmt drift, pre-push runs clippy + cargo-nextest, and commit-msg enforces Conventional Commits. CI's `Generated source freshness` job catches stale generated source server-side.

## Android cross-builds

`just build-apk` builds natively on Windows, Linux, or macOS - no WSL required.

The resolved SDK graph has no OpenSSL/native-TLS build requirement. The retired workaround is recorded in [Local patches](LOCAL_PATCHES.md#2-retired-sonos-sdk-tls-fork); Perl and WSL are not prerequisites.

Toolchain needed: Java 21, Android SDK platform 36 + build-tools 36, NDK auto-selected by Gradle via `flutter.ndkVersion` (install nothing manually - the first build pulls the exact NDK it wants). For a phone attached over USB, `adb` works directly - no WSL bridging needed.

## Version pin policy

Toolchain and tooling versions are pinned in multiple files. Dependabot covers most of them; a few require coordinated manual updates.

### Pinned in workflows (Dependabot updates these)

- `dtolnay/rust-toolchain@<version>` - bumping this **must** be paired with the manual updates below (the action ref is what CI uses; the toolchain file is the source of truth for local development).
- `subosito/flutter-action@vN` - major action version, automatic.
- All other `uses:` action refs.

### Manual bump required (Dependabot doesn't see these)

When the `dtolnay/rust-toolchain` Dependabot PR lands, update **in the same PR**:

- `rust-toolchain.toml` - `channel = "X.Y.Z"`
- `native/Cargo.toml` - `rust-version = "X.Y"` under `[workspace.package]`

For Flutter, no Dependabot coverage exists. `.fvmrc` at the repo root is the canonical Flutter version - the CI workflows read it (the `Read Flutter version` steps in the workflows), so bumping `.fvmrc` (`{"flutter": "X.Y.Z"}`) propagates automatically.

Other inline pins to grep for when a coordinated bump is needed:

- `cargo install flutter_rust_bridge_codegen --version X.Y.Z` (search all workflows and the README)
- `flutter_rust_bridge = "=X.Y.Z"` in `native/Cargo.toml` and `flutter_rust_bridge: X.Y.Z` in `app/pubspec.yaml`

The FRB codegen version and FRB crate version **must** stay aligned, or generated source will drift.

### Cargo/pub dependencies

Dependabot opens grouped weekly PRs for `cargo` (in `native/`) and `pub` (in `app/` and `app/rust_builder/`). A narrow subset auto-merges once the required checks pass, via `.github/workflows/dependabot-auto-merge.yml`: patch updates, plus minor updates on development-only dependencies. Everything else is reviewed and merged by hand - production minors (pre-1.0 crates treat minor as breaking by SemVer convention), all majors, and ANY bump touching the contract-pinned dependencies (`sonos-api` / `sonos-sdk-*` / `quick-xml` / `ureq` / `flutter_rust_bridge`, see AGENTS.md 2.1), which the workflow excludes even at patch level. For grouped PRs, fetch-metadata reports the highest bump in the group, so a group containing one production minor is held for review.

## Branch protection

`main` is protected by the `main-protect` ruleset (**Settings → Rules → Rulesets**, not the older Settings → Branches protection - `gh api .../branches/main/protection` reports "not protected"). Four checks are required: `Generated source freshness`, `Rust (lint + test)`, `Rust (supply-chain)`, and `Flutter (analyze + test)`. Check the live ruleset when changing merge policy; workflow definitions alone do not establish which checks are required.

`Android cross-compile (oto_native)` runs on every PR but is **not** in the required set, so it does not block a merge on its own.

The `build` workflow's `Debug APK` job also runs on PRs that touch Android-relevant paths (see its `pull_request` trigger), but is **not** a required check - it is informational for now. Promote it to required once it has a track record of staying green.

## Commit messages

Conventional Commits, lowercase scope when relevant. Enforced locally by the lefthook `commit-msg` hook and in CI on PR titles (`.github/workflows/pr-title.yml`); allowed types: feat, fix, chore, docs, style, refactor, perf, test, build, ci, revert.

```
chore(app): polish scaffolding, target Android 15+ (64-bit only)
feat(wire): add SSDP discovery loop
fix(android): release multicast lock after discovery fails
```

Keep the subject under ~72 chars and let the body explain _why_.

## Pull requests

- Run `just check` and `just test` locally before opening.
- Generated source must be regenerated and committed if any input changed.
- CI runs five jobs in parallel (`generated`, `rust`, `deny`, `android-rust`, `flutter`). Four of them block the merge - `android-rust` is informational (see [Branch protection](#branch-protection)). PRs touching Android-relevant paths additionally build the debug APK (~8 min, also not required).
