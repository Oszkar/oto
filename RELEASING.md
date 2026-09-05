# Releasing

`oto` is pre-1.0 and follows [Semantic Versioning][semver]. While on `0.y.z` the public surface and behavior may change between any releases.

## Source of truth

`app/pubspec.yaml` `version:` is canonical - the Flutter app is the only shippable artifact. Format: `MAJOR.MINOR.PATCH+BUILD`, where `+BUILD` is the Android `versionCode` and is incremented on every release.

`native/Cargo.toml` `[workspace.package] version` is kept equal to the `MAJOR.MINOR.PATCH` by hand. The `native/crates/*` are `publish = false`, so this is cosmetic - there is intentionally no sync tooling and no separate `VERSION` file (a third place would only drift).

## Cutting a release

0. Run the integration gate: the **integration-gate** workflow (Actions → integration-gate → Run workflow), or locally with `just test-integration` on a Windows desktop. It drives the full Dart → Rust → Dart event loop through the real FRB bridge against MockWire - coverage `ci.yml` cannot provide, because `flutter test` there picks up `app/test/**` only and `integration_test/` needs a display target. Not a required check on PRs; this is the point at which it runs.
1. Choose the version per SemVer. Pre-1.0: breaking changes bump MINOR.
2. Bump `app/pubspec.yaml` `version:` (including `+BUILD`), `native/Cargo.toml` `[workspace.package] version`, and `app/lib/src/app_info.dart`'s `version` constant to match. `flutter test` catches drift on the last one (`settings_screen_test.dart`'s "AppInfo version stays aligned with pubspec base version").
3. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and add a fresh empty `## [Unreleased]` above it. Update the compare-link footer too: repoint `[Unreleased]` at `compare/vX.Y.Z...HEAD` and add a `[X.Y.Z]: compare/<prev>...vX.Y.Z` line.
4. Update `docs/ROADMAP.md`'s milestone status when the release completes a listed milestone. Keep release-by-release detail in the changelog.
5. Commit: `chore: release vX.Y.Z`. Merge to `main` as usual.
6. Tag the merge commit on `main`: `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z`.
7. Create the GitHub Release for that tag; use the CHANGELOG section as the release notes.

## Planned v0.7.0 test distribution

This is the agreed target process, not an implemented workflow. The manual procedure above and debug-only build workflow remain current until this work lands. Scope and acceptance criteria live in the [roadmap](docs/ROADMAP.md#v07---hardening--test-distribution).

### Packages and signing

- **Android:** release-mode APK for the supported 64-bit ABIs, signed with a dedicated, stable test-distribution key. Use a separate application ID from future Play distribution so different signing identities do not conflict. Document the exact ID when implemented; test and future Play installs have separate local preferences. Existing debug installs are not promised an in-place migration.
- **Windows:** unsigned x64 portable release ZIP containing the executable, Flutter data, native libraries, and required redistributable runtime files. Verify extraction and launch on a clean Windows machine; document any prerequisites and the possible unrecognized-app warning. No installer is required for v0.7.0.
- **Metadata:** versioned asset filenames, SHA-256 checksums, source commit, workflow-run provenance, and concise install/upgrade instructions. Attach these to the GitHub Release; temporary Actions artifacts alone do not meet the persistence requirement.

The project owner approved creating the dedicated Android test key and storing it and its credentials in GitHub Actions secrets, with an independently secured backup. The key and credentials must never enter the repository, artifacts, or logs. Confirm backup custody before relying on the key for update continuity. Production/Play signing remains a separate future decision.

### Candidate workflow

1. Merge the versioned candidate through normal PR review, then create its annotated release tag on `main`.
2. Run the release workflow against that tag. Verify the tag matches the canonical app version, the Rust workspace version, and `AppInfo.version`; record the Android build number. Restrict signing secrets to trusted release execution, never PR builds.
3. Require successful validation for the candidate commit, including Windows FRB integration. Build the Android and Windows release packages from that same tag and attach them with checksums/provenance to a draft GitHub Release. Keep the mock-based debug integration gate: release builds deliberately disable its injection seam.
4. Install and validate those exact packages on Windows and Android, including real Sonos hardware acceptance. If a fix changes the candidate, produce and validate a new candidate with explicit provenance; do not substitute untested assets.
5. Publish the draft after acceptance, using the changelog section as release notes. Publication must not rebuild the packages. Keep published tags and assets immutable; ship corrections under a new version.

GitHub Release downloads are the v0.7.0 distribution channel. Google Play publishing is desired later, but is outside this milestone and does not require an approved Play account now. Production Android signing, Windows code signing, and Windows installers remain deferred.

[semver]: https://semver.org/spec/v2.0.0.html
