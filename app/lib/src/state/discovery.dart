import 'dart:io' show Platform;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../platform/android_multicast_lock.dart';
import '../rust/api.dart' as rust_api;

part 'discovery.g.dart';

/// Deferred LAN discovery. The Rust `discover()` blocks ~3–5 s and FRB
/// runs it off the UI isolate, so this is a Future provider: AsyncValue
/// gives loading / error / data; retry via `ref.invalidate` / `ref.refresh`.
///
/// On Android (v0.5 S3) the SSDP window is wrapped in a held
/// `WifiManager.MulticastLock` — without it Android drops the inbound
/// multicast replies and discovery finds nothing on release builds. The
/// lock is released in a `finally` so a failed discover still frees it.
/// Other platforms call `discover()` directly (no channel handler exists).
@riverpod
Future<rust_api.Topology> discovery(Ref ref) async {
  if (Platform.isAndroid) {
    await AndroidMulticastLock.acquire();
    try {
      return await rust_api.discover();
    } finally {
      await AndroidMulticastLock.release();
    }
  }
  return rust_api.discover();
}
