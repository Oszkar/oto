import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oto/main.dart';
import 'package:oto/src/rust/frb_generated.dart';

/// Bridge smoke: boots the full Flutter app on a host device, which forces
/// `RustLib.init()` to dynamically load the FRB cdylib (`oto_native`). The
/// rest of the harness is mocked or unit-tested in `app/test/`; this is the
/// only test that exercises the actual native artefact and its loader path.
///
/// Not gated by CI today (Flutter's `integration_test` needs a display /
/// device target — neither the `ubuntu-latest` CI runners nor any of the
/// matrix runs in `build.yml` are configured for that). Run manually via
/// `just test-integration` against a connected device / desktop platform.
/// Revisit gating when v0.5 lands real UI and the smoke earns its keep.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  testWidgets('app boots with RustLib initialised', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: OtoApp()));
    // The neutral placeholder scaffold (`main.dart`'s `HomePage`) renders
    // exactly this string until v0.5 brings real UI. Asserting on it
    // catches both "FRB cdylib failed to load" and "widget tree never
    // mounted" without requiring any particular post-v0.5 layout.
    expect(find.text('oto'), findsOneWidget);
  });
}
