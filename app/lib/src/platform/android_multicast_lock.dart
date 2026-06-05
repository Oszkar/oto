/// Dart shim over the `me.oszkar.oto/multicast_lock` MethodChannel.
///
/// Android silently drops inbound SSDP multicast without a held
/// `WifiManager.MulticastLock`, so release-build discovery finds nothing.
/// [discoveryProvider] acquires the lock around the `discover()` SSDP window
/// and releases it after (success or error). Android-only — callers guard
/// with `Platform.isAndroid`; the channel has no handler on other platforms.
library;

import 'package:flutter/services.dart';

class AndroidMulticastLock {
  const AndroidMulticastLock._();

  static const _channel = MethodChannel('me.oszkar.oto/multicast_lock');

  /// Acquire the multicast lock (reference-counted on the native side).
  static Future<void> acquire() => _channel.invokeMethod<void>('acquire');

  /// Release a previously-acquired lock. Safe to call even if not held —
  /// the native handler guards against an unbalanced release.
  static Future<void> release() => _channel.invokeMethod<void>('release');
}
