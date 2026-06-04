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

Generated source (`app/lib/src/rust/`, `native/src/frb_generated*`, `**/*.g.dart`) is committed. Always run `just gen` before committing changes to inputs. The Lefthook pre-commit hook (`just install-hooks`) catches stale generated source locally; CI's `Generated source freshness` job catches it server-side.

## Android cross-builds — build on Linux, macOS, or WSL

**Recommended: build the Android APK from Linux, macOS, or WSL.** The Android NDK ships no system OpenSSL, so the workspace's `[target.'cfg(target_os = "android")'.dependencies] openssl = { features = ["vendored"] }` compiles OpenSSL from source, and OpenSSL's `Configure` is Perl-driven. Linux/macOS ship a complete Perl 5 by default, so `just build-apk` works out of the box; CI uses `ubuntu-latest` for the same reason. WSL counts as Linux here.

Validated 2026-05-30 on WSL2 (Ubuntu) → real Pixel 7a, debug APK, discovery + events end-to-end (see [docs/evidence/v0.5-android-debug.md](docs/evidence/v0.5-android-debug.md)). Toolchain there: Java 21, Android SDK platform 36 + build-tools 36, NDK auto-selected by Gradle via `flutter.ndkVersion` (install nothing manually — the first build pulls the exact NDK it wants). For a phone attached to Windows, bridge it into WSL with wireless adb (`adb tcpip 5555` on the host, `adb connect <phone-ip>:5555` inside WSL).

**Windows-native cross-build is discouraged.** It works only with a Unix-aware Perl carrying the full standard module set, which is per-developer toolchain debt:
- **Strawberry Perl** (MSWin32) — fails: "doesn't produce Unix-like paths" (OpenSSL's Linux config wants forward slashes).
- **Git-for-Windows' bundled msys perl** — right path semantics, but minimal; missing standard modules like `Locale::Maketext::Simple` that `Configure` loads via `IPC::Cmd`.
- **msys2** (`winget install MSYS2.MSYS2`, then prepend `C:\msys64\usr\bin` to PATH so `cargo` finds its full Perl) is the only Windows path that works — kept here for reference, but prefer WSL.

Post-1.0 follow-up (per ROADMAP project-bound open items): a rustls migration via `[patch.crates-io]` would drop the vendored-OpenSSL/Perl requirement entirely. Document any new build-target prereqs here as they surface.

## Version pin policy

Toolchain and tooling versions are pinned in multiple files. Dependabot covers most of them; a few require coordinated manual updates.

### Pinned in workflows (Dependabot updates these)

- `dtolnay/rust-toolchain@<version>` — bumping this **must** be paired with the manual updates below (the action ref is what CI uses; the toolchain file is the source of truth for local development).
- `subosito/flutter-action@vN` — major action version, automatic.
- All other `uses:` action refs.

### Manual bump required (Dependabot doesn't see these)

When the `dtolnay/rust-toolchain` Dependabot PR lands, update **in the same PR**:

- `rust-toolchain.toml` — `channel = "X.Y.Z"`
- `native/Cargo.toml` — `rust-version = "X.Y"` under `[workspace.package]`

For Flutter, no Dependabot coverage exists. Bump together when needed:

- `.github/workflows/ci.yml` — `flutter-version: X.Y.Z` (both occurrences)
- `.github/workflows/build.yml` — `flutter-version: X.Y.Z`
- `README.md` — "currently 3.38.x" mention

Other inline pins to grep for when a coordinated bump is needed:

- `cargo install flutter_rust_bridge_codegen --version X.Y.Z` (both workflows)
- `flutter_rust_bridge = "=X.Y.Z"` in `native/Cargo.toml`

The FRB codegen version and FRB crate version **must** stay aligned, or generated source will drift.

### Cargo/pub dependencies

Dependabot opens grouped weekly PRs for `cargo` (in `native/`) and `pub` (in `app/` and `app/rust_builder/`). All bumps — patch, minor, and major — are reviewed and merged by hand; nothing auto-merges (pre-1.0 crates treat minor as breaking by SemVer convention, and the maintainer owns merges/tags/releases).

## Branch protection

`main` is protected: a PR cannot merge until the `ci` workflow's checks pass — `Generated source freshness`, `Rust (lint + test)`, `Rust (supply-chain)`, `Android cross-compile (oto_native)`, and `Flutter (analyze + test)`. This gates manual merges (including Dependabot PRs) so nothing lands red. Configured under **Settings → Branches** (or via the `gh api .../branches/main/protection` call).

## Commit messages

Conventional Commits, lowercase scope when relevant:

```
chore(app): polish scaffolding, target Android 15+ (64-bit only)
feat(core): add SSDP discovery loop
fix(android): widen multicast lock to cover event subscription
```

Keep the subject under ~72 chars and let the body explain *why*.

## Pull requests

- Run `just check` and `just test` locally before opening.
- Generated source must be regenerated and committed if any input changed.
- CI runs five jobs in parallel (`generated`, `rust`, `deny`, `android-rust`, `flutter`); all must pass before merge.
