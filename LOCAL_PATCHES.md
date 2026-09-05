# Local patches

Catalog of local changes to vendored or forked third-party code. Re-apply active entries when syncing their upstream source. Retired entries preserve history and must not be reintroduced automatically.

## Inventory

| # | File | Patch summary | Why | Status |
|---|------|---------------|-----|--------|
| 1 | `app/rust_builder/cargokit/gradle/plugin.gradle` | Drop 32-bit Android ABIs from the Rust build target list | Project targets `minSdk = 35` (Android 15+, arm64 + x86_64 only); building `i686-linux-android` and `armv7-linux-androideabi` is wasted work and the targets aren't installed by `rust-toolchain.toml` | Active |
| 2 | Former `sonos-sdk` fork via `[patch.crates-io]` | Strip unused native TLS | Upstream 0.8 removes the affected dependencies | Retired 2026-09-05 |
| 3 | `app/rust_builder/macos/oto_native.podspec` | Append `-framework SystemConfiguration` to `OTHER_LDFLAGS` | Historically required by `reqwest` proxy detection. That dependency disappeared with SDK 0.8.0; remove the flag after a macOS build confirms it is unnecessary. macOS is a dev-only target (not shipped; oto ships Windows + Android) | Retained pending macOS validation |

---

## 1. cargokit/gradle/plugin.gradle - drop 32-bit ABIs

**File:** `app/rust_builder/cargokit/gradle/plugin.gradle` **Upstream:** https://github.com/irondash/cargokit **Affected block:** `CargoKitPlugin.apply` → the `variants.all { variant -> ... }` closure, around the platform-list construction.

### What the patch does

1. Replaces the unconditional `platforms.add("android-x86")` (32-bit emulator target) for debug builds with `platforms.add("android-x64")` so debug builds use the 64-bit emulator target instead.
2. Adds a filtering pass right after platform-list construction that strips `android-arm` (armeabi-v7a) and `android-x86` (i686) from the list, regardless of where they came from (`FlutterPluginUtils.getTargetPlatforms` may add them based on app config).

### Why we patch instead of using config

Cargokit has **no config knob** for filtering ABIs out of the platform list - the hardcoded `platforms.add("android-x86")` and the unconditional inclusion of whatever Flutter returns are not overridable from `cargokit { ... }` in the consuming `build.gradle`. Until upstream accepts a configuration option, patching is the only way to skip 32-bit builds.

Why not just let cargo fail on the missing 32-bit Rust targets? Because the failure mode is opaque (`error: the target "i686-linux-android" is not installed`) - every fresh contributor hits it. The patch fails fast and quietly with the right behavior.

### Diff (for re-application)

```groovy
// In the variants.all { variant -> ... } closure, replace:

if (buildType == "debug") {
    platforms.add("android-x86")
}

// with:

if (buildType == "debug") {
    // LOCAL PATCH (oto): upstream also adds "android-x86"; we target Android 15+ (64-bit only).
    platforms.add("android-x64")
}

// LOCAL PATCH (oto): drop 32-bit ABIs - project minSdk is 35 (Android 15+).
// Re-apply if syncing cargokit from upstream.
platforms = platforms.findAll { it != "android-arm" && it != "android-x86" }.unique()
```

### Upstream tracking

No upstream issue filed yet. If we file one, link it here. The right upstream shape would be a Gradle DSL block like:

```groovy
cargokit {
    libname = "oto_native"
    manifestDir = "../../../native"
    abiFilters = ["arm64-v8a", "x86_64"]   // <-- desired
}
```

mapped onto cargo target triples internally. Until then: patch.

---

## 2. sonos-sdk fork - drop unused `native-tls` backend

**Retired 2026-09-05 with the aligned SDK 0.8.0 upgrade.** Upstream
[#107](https://github.com/tatimblin/sonos-sdk/pull/107) replaced the old HTTP
dependencies. oto now resolves the full SDK family from crates.io, with no
`[patch.crates-io]` block or fork allowlist. `reqwest`, `warp`, `h2`,
`native-tls`, and OpenSSL are absent from the resolved graph. The rationale
and diff below describe the former 0.5.2 workaround, not current setup.

**Repo:** [`Oszkar/sonos-sdk`](https://github.com/Oszkar/sonos-sdk) (fork of [`tatimblin/sonos-sdk`](https://github.com/tatimblin/sonos-sdk)) **Branch/tag:** `oto-android-tls-patch` / `oto-android-tls-patch-v0.5.2`, cut from upstream tag `sonos-api-v0.5.2`. **Wired in via:** `[patch.crates-io]` in `native/Cargo.toml`, pinned to commit `181e6bf6ac23d57a2c5b0f0766f220b55866afd6`. Also requires `native/deny.toml`'s `[sources] allow-git` to list the fork URL.

### What the patch does

Three crates in the `sonos-sdk` family declare `reqwest = "0.11"` with implicit default features, which pull `native-tls` → `openssl-sys` on non-Windows/macOS targets. Confirmed by reading each crate's source at the pinned tag:

- `sonos-discovery/Cargo.toml`: `reqwest` is used, but only for plain `http://` GETs of device-description XML (Sonos never serves HTTPS on a LAN). Changed to `default-features = false, features = ["blocking"]` - keeps working, just drops the unused TLS backend.
- `callback-server/Cargo.toml`: `reqwest` had **zero references** anywhere in the crate's source. Removed the dependency entirely.
- `sonos-stream/Cargo.toml`: same - **zero references**. Removed entirely.
- `sonos-api`'s own Cargo.toml is unmodified but is *also* listed in `[patch.crates-io]` (unchanged content, repointed source only) - required because it path-depends on `sonos-discovery` within the same repo checkout. Without repointing it too, the graph ends up with two distinct `sonos-api` instances (crates.io vs git, since `sonos-sdk-event-manager`/`sonos-sdk-state` are unpatched and still resolve `sonos-api` from crates.io) whose types don't unify - a compile error, not just a lint.

### Why we patch instead of waiting on upstream

`sonos-api` is pinned exact (`=0.5.2`, see AGENTS.md §2.1) and `tatimblin/sonos-sdk` is a small, slow-moving upstream - [`#76`](https://github.com/tatimblin/sonos-sdk/issues/76), an unrelated but higher-severity bug, sat with zero response for 1.5 months. No config knob exists to strip TLS features from a pinned dependency's dependency short of a source-level fork.

### Diff (for re-application)

```diff
# sonos-discovery/Cargo.toml
-reqwest = { version = "0.11", features = ["blocking"] }
+reqwest = { version = "0.11", default-features = false, features = ["blocking"] }

# callback-server/Cargo.toml
-reqwest = "0.11"
 (line removed)

# sonos-stream/Cargo.toml
-reqwest = "0.11"
 (line removed)
```

### Upstream tracking

No upstream issue filed yet. Link it here once one exists.

---

## 3. macos/oto_native.podspec - link SystemConfiguration.framework

**File:** `app/rust_builder/macos/oto_native.podspec` **Affected block:** the second `s.pod_target_xcconfig` (`OTHER_LDFLAGS`).

The explanation below records the original failure. SDK 0.8.0 removed
`reqwest` and `system-configuration` from our dependency graph. The flag is
retained until a macOS build validates its removal; it is no longer a
known requirement of the current dependency graph.

### What the patch does

Appends `-framework SystemConfiguration` to the existing `-force_load ${BUILT_PRODUCTS_DIR}/liboto_native.a`:

```ruby
'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/liboto_native.a -framework SystemConfiguration',
```

### Why

`liboto_native` pulls the `system_configuration` crate transitively (via `reqwest`'s platform proxy detection). Its `SC*` / `kSC*` symbols live in Apple's `SystemConfiguration.framework`. The crate emits `cargo:rustc-link-lib=framework=SystemConfiguration`, but a Rust **staticlib** can't carry that directive to Xcode's final link step, so the macOS Runner fails with `Undefined symbols ... _SCDynamicStoreCopyProxies`, `_SCNetworkInterfaceCopyAll`, `_kSCNetworkInterfaceTypeEthernet`, etc. macOS is a **dev-only** target (for previewing e.g. the showcase off a Mac); oto ships Windows + Android, so this isn't wired into CI. The identical latent gap exists in `ios/oto_native.podspec` - apply the same fix there if iOS is ever built.

### Re-application

`flutter create`-generated; regenerated only if the platform folder is recreated. After a regen, re-append the `-framework SystemConfiguration` flag and confirm with `flutter build macos -t lib/showcase/main.dart` (or `just showcase` → macOS).

---

## Re-application procedure

### Cargokit (entry #1)

1. Vendor the new Cargokit tree (replace `app/rust_builder/cargokit/`).
2. Locate the affected block and re-apply the diff. The `LOCAL PATCH (oto):` comments make the touched regions grep-able: `grep -rn "LOCAL PATCH (oto)" app/rust_builder/`.
3. Run `just build-apk` to confirm. If cargo errors with "missing target i686-linux-android" or "armv7-linux-androideabi", the patch didn't take.
4. Update this file if the patch's location or content changed.

### sonos-sdk fork (entry #2)

Historical procedure only: entry #2 is retired. Future SDK upgrades should
first check upstream dependencies rather than recreate this fork.

1. If bumping the `sonos-api`/`sonos-sdk-*` pin, re-cut the `oto-android-tls-patch` branch from the new upstream tag in the `Oszkar/sonos-sdk` fork and re-apply the three edits above.
2. Update the `rev` in `native/Cargo.toml`'s `[patch.crates-io]` block to the new commit.
3. Run `cargo check --workspace` in `native/` and confirm `openssl`/`openssl-sys`/`native-tls` don't reappear in `Cargo.lock` (`grep -i "^name = \"openssl\|native-tls\"" native/Cargo.lock` should be empty).
4. Run `just check` and `just build-apk` to confirm.

For either patch: if it becomes unnecessary (e.g., upstream lands a fix), strip it and move the entry to a "Retired" section below with the date and the upstream commit/version that obviated it.
