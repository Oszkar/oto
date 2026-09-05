# Local patches

Local third-party integration changes. Reapply the active Cargokit patch when updating the vendored tree; do not restore retired workarounds.

| Entry | Location | Status |
| --- | --- | --- |
| 1 | `app/rust_builder/cargokit/gradle/plugin.gradle` | Active: build only 64-bit Android ABIs |
| 2 | Former `sonos-sdk` fork | Retired with SDK 0.8.0 |
| 3 | `app/rust_builder/macos/oto_native.podspec` | Retained pending macOS validation |

## 1. cargokit/gradle/plugin.gradle - drop 32-bit ABIs

**File:** `app/rust_builder/cargokit/gradle/plugin.gradle` **Upstream:** https://github.com/irondash/cargokit **Affected block:** `CargoKitPlugin.apply` → the `variants.all { variant -> ... }` closure, around the platform-list construction.

### What the patch does

1. Replaces the unconditional `platforms.add("android-x86")` (32-bit emulator target) for debug builds with `platforms.add("android-x64")` so debug builds use the 64-bit emulator target instead.
2. Adds a filtering pass right after platform-list construction that strips `android-arm` (armeabi-v7a) and `android-x86` (i686) from the list, regardless of where they came from (`FlutterPluginUtils.getTargetPlatforms` may add them based on app config).

### Why we patch instead of using config

Cargokit has **no config knob** for filtering ABIs out of the platform list - the hardcoded `platforms.add("android-x86")` and the unconditional inclusion of whatever Flutter returns are not overridable from `cargokit { ... }` in the consuming `build.gradle`. Until upstream accepts a configuration option, patching is the only way to skip 32-bit builds.

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

### Updating Cargokit

1. Update the vendored `app/rust_builder/cargokit/` tree.
2. Reapply the platform filtering above unless the new version provides equivalent configuration. Locate the edits with `rg "LOCAL PATCH" app/rust_builder/`.
3. Run `just build-apk`; neither `i686-linux-android` nor `armv7-linux-androideabi` should be requested.
4. Update this entry if the patch or its location changes.

## 2. Retired sonos-sdk TLS fork

Retired 2026-09-05 with SDK 0.8.0. The older SDK graph pulled unused native TLS through `reqwest`, forcing Android builds through OpenSSL and Perl. oto temporarily patched it through the `Oszkar/sonos-sdk` fork. SDK 0.8 removed the affected HTTP dependencies, so the full SDK family now resolves from crates.io without `[patch.crates-io]` or a fork allowlist.

Do not recreate the fork when upgrading. Check `native/Cargo.lock` and run `just check` and `just build-apk` to catch dependency and Android build regressions. The former patch is recoverable from `git log -- LOCAL_PATCHES.md`.

## 3. macOS SystemConfiguration linker flag

`app/rust_builder/macos/oto_native.podspec` retains:

```ruby
'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/liboto_native.a -framework SystemConfiguration',
```

This fixed unresolved `SC*` symbols when `reqwest` used Apple's proxy detection: Rust static libraries do not carry framework-link directives into Xcode's final link. SDK 0.8 removed that dependency path. Remove the flag after verifying `flutter build macos -t lib/showcase/main.dart` from `app/` without it. macOS is not a supported shipping target; do not copy this workaround to iOS without a demonstrated linker failure.
