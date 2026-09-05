# Rust build plugin

This Cargokit Flutter plugin builds [`native/`](../../native/) into the platform library loaded by FRB. Its Gradle, CMake, and podspec files contain relative paths to that workspace; update them if either directory moves.

Vendored modifications and validation steps are documented in [Local patches](../../LOCAL_PATCHES.md).
