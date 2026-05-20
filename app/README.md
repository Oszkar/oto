# oto

Flutter application shell for oto.

## Development

Run app-level commands from this directory, or use the root `Makefile` / `justfile` from the repository root.

Common local commands:

- `flutter pub get`
- `flutter analyze`
- `flutter test`

Generated FRB and Riverpod source is committed. Regenerate it from the repository root with `just gen` or `make gen` after changing the Rust bridge API or `@riverpod` providers.
