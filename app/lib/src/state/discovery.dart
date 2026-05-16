import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../rust/api.dart' as rust_api;

part 'discovery.g.dart';

/// Deferred LAN discovery. The Rust `discover()` blocks ~3–5 s and FRB
/// runs it off the UI isolate, so this is a Future provider: AsyncValue
/// gives loading / error / data; retry via `ref.invalidate` / `ref.refresh`.
@riverpod
Future<rust_api.Topology> discovery(Ref ref) => rust_api.discover();
