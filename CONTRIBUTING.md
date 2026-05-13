# Contributing to oto

Short doc focused on the non-obvious bits. For setup/commands, see
[README.md](README.md).

## Development workflow

The repo uses `just` (preferred) or `make`. Common loop:

```bash
just gen        # regenerate FRB + Riverpod source after editing native/src/api.rs
                # or any @riverpod-annotated Dart
just check      # cargo fmt + clippy + flutter analyze
just test       # cargo nextest + flutter test
```

Generated source (`app/lib/src/rust/`, `native/src/frb_generated*`, `**/*.g.dart`)
is committed. Always run `just gen` before committing changes to inputs.
The Lefthook pre-commit hook (`just install-hooks`) catches stale generated
source locally; CI's `Generated source freshness` job catches it server-side.

## Version pin policy

Toolchain and tooling versions are pinned in multiple files. Dependabot
covers most of them; a few require coordinated manual updates.

### Pinned in workflows (Dependabot updates these)

- `dtolnay/rust-toolchain@<version>` — bumping this **must** be paired with
  the manual updates below (the action ref is what CI uses; the toolchain
  file is the source of truth for local development).
- `subosito/flutter-action@vN` — major action version, automatic.
- All other `uses:` action refs.

### Manual bump required (Dependabot doesn't see these)

When the `dtolnay/rust-toolchain` Dependabot PR lands, update **in the
same PR**:

- `rust-toolchain.toml` — `channel = "X.Y.Z"`
- `native/Cargo.toml` — `rust-version = "X.Y"` under `[workspace.package]`

For Flutter, no Dependabot coverage exists. Bump together when needed:

- `.github/workflows/ci.yml` — `flutter-version: X.Y.Z` (both occurrences)
- `.github/workflows/build.yml` — `flutter-version: X.Y.Z`
- `README.md` — "currently 3.38.x" mention

Other inline pins to grep for when a coordinated bump is needed:

- `cargo install flutter_rust_bridge_codegen --version X.Y.Z` (both workflows)
- `flutter_rust_bridge = "=X.Y.Z"` in `native/Cargo.toml`

The FRB codegen version and FRB crate version **must** stay aligned, or
generated source will drift.

### Cargo/pub dependencies

Dependabot opens grouped weekly PRs for `cargo` (in `native/`) and `pub`
(in `app/` and `app/rust_builder/`). Review minor/major bumps; patch
updates auto-merge once CI passes (see below).

## Auto-merge

`.github/workflows/dependabot-auto-merge.yml` enables auto-merge for
**patch-level** Dependabot PRs after CI passes. Minor and major bumps stay
manual so a human can scan changelogs (pre-1.0 crates treat minor as
breaking by SemVer convention).

Prerequisites — these are repo settings, not files, so set them once in
the GitHub UI:

- **Settings → General → Pull Requests** → enable **Allow auto-merge**.
- **Settings → Branches** → branch protection for `main` requiring the
  `ci` workflow checks to pass. Without this, auto-merge fires immediately
  with no gating.

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
- CI runs three jobs in parallel (`generated`, `rust`, `flutter`); all
  must pass before merge.
