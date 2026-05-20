# Local patches

Catalog of every file under `app/rust_builder/cargokit/` (and any other vendored third-party code) that we've modified locally. Anyone syncing the vendored source from upstream **must** re-apply each entry here, or the upstream version will silently replace our patch and reintroduce the bug it fixed.

## Inventory

| # | File | Patch summary | Why | Status |
|---|------|---------------|-----|--------|
| 1 | `app/rust_builder/cargokit/gradle/plugin.gradle` | Drop 32-bit Android ABIs from the Rust build target list | Project targets `minSdk = 35` (Android 15+, arm64 + x86_64 only); building `i686-linux-android` and `armv7-linux-androideabi` is wasted work and the targets aren't installed by `rust-toolchain.toml` | Active |

---

## 1. cargokit/gradle/plugin.gradle — drop 32-bit ABIs

**File:** `app/rust_builder/cargokit/gradle/plugin.gradle` **Upstream:** https://github.com/irondash/cargokit **Affected block:** `CargoKitPlugin.apply` → the `variants.all { variant -> ... }` closure, around the platform-list construction.

### What the patch does

1. Replaces the unconditional `platforms.add("android-x86")` (32-bit emulator target) for debug builds with `platforms.add("android-x64")` so debug builds use the 64-bit emulator target instead.
2. Adds a filtering pass right after platform-list construction that strips `android-arm` (armeabi-v7a) and `android-x86` (i686) from the list, regardless of where they came from (`FlutterPluginUtils.getTargetPlatforms` may add them based on app config).

### Why we patch instead of using config

Cargokit has **no config knob** for filtering ABIs out of the platform list — the hardcoded `platforms.add("android-x86")` and the unconditional inclusion of whatever Flutter returns are not overridable from `cargokit { ... }` in the consuming `build.gradle`. Until upstream accepts a configuration option, patching is the only way to skip 32-bit builds.

Why not just let cargo fail on the missing 32-bit Rust targets? Because the failure mode is opaque (`error: the target "i686-linux-android" is not installed`) — every fresh contributor hits it. The patch fails fast and quietly with the right behavior.

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

// LOCAL PATCH (oto): drop 32-bit ABIs — project minSdk is 35 (Android 15+).
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

## Re-application procedure

When updating vendored Cargokit:

1. Vendor the new Cargokit tree (replace `app/rust_builder/cargokit/`).
2. For each entry in **Inventory** above, locate the affected block and re-apply the diff. The `LOCAL PATCH (oto):` comments make the touched regions grep-able: `grep -rn "LOCAL PATCH (oto)" app/rust_builder/`.
3. Run `just build-apk` to confirm. If cargo errors with "missing target i686-linux-android" or "armv7-linux-androideabi", patch #1 didn't take.
4. Update this file if the patch's location or content changed.

If a patch becomes unnecessary (e.g., upstream landed a config option), strip it and move the entry to a "Retired" section below with the date and the upstream commit/version that obviated it.
