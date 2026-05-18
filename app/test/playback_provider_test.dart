import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/playback.dart';

void main() {
  test('playback providers are wired (compile-level proof, P2)', () {
    // `speakerStateProvider` exists only if playback.dart compiled — and
    // playback.dart calls the FRB `rust_api.speakerState` binding, so this
    // also guards that the binding is present. The live SOAP call needs a
    // real device; that is the user-run integration path.
    expect(speakerStateProvider, isNotNull);
    // `playbackCommandsProvider` guards the six command bindings.
    expect(playbackCommandsProvider, isNotNull);
  });
}
