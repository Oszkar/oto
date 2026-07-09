/// Tests for the [AndroidMulticastLock] MethodChannel shim: verify
/// `acquire`/`release` send the expected method names over the
/// `me.oszkar.oto/multicast_lock` channel. The native handler and the
/// `Platform.isAndroid`-gated wrapping in `discoveryProvider` are exercised
/// only on a real Android device (hardware acceptance) - here we pin the
/// Dart→platform contract with a mock channel, which runs on any host.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/platform/android_multicast_lock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('me.oszkar.oto/multicast_lock');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('acquire sends "acquire" over the channel', () async {
    await AndroidMulticastLock.acquire();
    expect(calls, ['acquire']);
  });

  test('release sends "release" over the channel', () async {
    await AndroidMulticastLock.release();
    expect(calls, ['release']);
  });

  test('acquire-then-release sends both, in order', () async {
    await AndroidMulticastLock.acquire();
    await AndroidMulticastLock.release();
    expect(calls, ['acquire', 'release']);
  });
}
