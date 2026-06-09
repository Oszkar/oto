# Releasing

`oto` is pre-1.0 and follows [Semantic Versioning][semver]. While on `0.y.z` the public surface and behavior may change between any releases.

## Source of truth

`app/pubspec.yaml` `version:` is canonical - the Flutter app is the only shippable artifact. Format: `MAJOR.MINOR.PATCH+BUILD`, where `+BUILD` is the Android `versionCode` and is incremented on every release.

`native/Cargo.toml` `[workspace.package] version` is kept equal to the `MAJOR.MINOR.PATCH` by hand. The `native/crates/*` are `publish = false`, so this is cosmetic - there is intentionally no sync tooling and no separate `VERSION` file (a third place would only drift).

## Cutting a release

1. Choose the version per SemVer. Pre-1.0: breaking changes bump MINOR.
2. Bump `app/pubspec.yaml` `version:` (including `+BUILD`) and `native/Cargo.toml` `[workspace.package] version` to match.
3. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and add a fresh empty `## [Unreleased]` above it.
4. Commit: `chore(release): vX.Y.Z`. Merge to `main` as usual.
5. Tag the merge commit on `main`: `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z`.
6. Create the GitHub Release for that tag; use the CHANGELOG section as the release notes.

## Deliberately deferred

Not done yet, on purpose - revisit once there is a signed, distributable build worth shipping:

- **No release binaries.** Builds are debug-only and Android release signing is not set up; no installers are attached to releases.
- **No release CI.** Tagging and the GitHub Release are manual.
- **No conventional-commit enforcement.**

[semver]: https://semver.org/spec/v2.0.0.html
