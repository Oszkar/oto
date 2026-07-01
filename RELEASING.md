# Releasing

`oto` is pre-1.0 and follows [Semantic Versioning][semver]. While on `0.y.z` the public surface and behavior may change between any releases.

## Source of truth

`app/pubspec.yaml` `version:` is canonical - the Flutter app is the only shippable artifact. Format: `MAJOR.MINOR.PATCH+BUILD`, where `+BUILD` is the Android `versionCode` and is incremented on every release.

`native/Cargo.toml` `[workspace.package] version` is kept equal to the `MAJOR.MINOR.PATCH` by hand. The `native/crates/*` are `publish = false`, so this is cosmetic - there is intentionally no sync tooling and no separate `VERSION` file (a third place would only drift).

## Cutting a release

1. Choose the version per SemVer. Pre-1.0: breaking changes bump MINOR.
2. Bump `app/pubspec.yaml` `version:` (including `+BUILD`) and `native/Cargo.toml` `[workspace.package] version` to match.
3. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and add a fresh empty `## [Unreleased]` above it. Update the compare-link footer too: repoint `[Unreleased]` at `compare/vX.Y.Z...HEAD` and add a `[X.Y.Z]: compare/<prev>...vX.Y.Z` line.
4. Flip the shipped version's status to "released" in `docs/ROADMAP.md`'s status table, and add its checkmark in `README.md`'s milestone table - same commit, so neither doc is ever stale relative to what's tagged.
5. Commit: `chore: release vX.Y.Z`. Merge to `main` as usual.
6. Tag the merge commit on `main`: `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z`.
7. Create the GitHub Release for that tag; use the CHANGELOG section as the release notes.

## Deliberately deferred

Not done yet, on purpose - revisit once there is a signed, distributable build worth shipping:

- **No release binaries.** Builds are debug-only and Android release signing is not set up; no installers are attached to releases.
- **No release CI.** Tagging and the GitHub Release are manual.

Conventional Commits are no longer deferred: they are enforced locally by the lefthook `commit-msg` hook (`.lefthook/commit-msg/conventional.sh`) and in CI by the PR-title workflow (`.github/workflows/pr-title.yml`), which lints the PR title - the only line that lands on `main` under squash-merge.

[semver]: https://semver.org/spec/v2.0.0.html
