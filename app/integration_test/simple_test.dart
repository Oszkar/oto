import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oto/src/rust/frb_generated.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/ui/shell/oto_app.dart';

/// Bridge smoke: boots the full Flutter app on a host device, which forces
/// `RustLib.init()` to dynamically load the FRB cdylib (`oto_native`). The
/// rest of the harness is mocked or unit-tested in `app/test/`; this is the
/// only test that exercises the actual native artefact and its loader path.
///
/// Runs as the release gate (RELEASING.md step 0) via the `integration-gate`
/// workflow on windows-latest, or locally with `just test-integration`. Not
/// part of `ci.yml`: Flutter's `integration_test` needs a display target and
/// ubuntu-latest has none.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  testWidgets('app boots with RustLib initialised', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsRepositoryProvider.overrideWithValue(PrefsRepository(prefs)),
        ],
        child: const OtoApp(),
      ),
    );
    await tester.pump();
    // Assert on the app root, not on anything inside Home. This used to check
    // for the placeholder Home's loading spinner, which v0.6 removed when the
    // real HomeScreen landed - so the smoke sat red and nobody noticed,
    // because nothing ran it. Keep the assertion layout-agnostic so it
    // survives the next UI change too.
    //
    // "FRB cdylib failed to load" is already caught upstream: `RustLib.init()`
    // in setUpAll throws if the native artefact can't be loaded. What this
    // adds is that the widget tree actually mounts on top of it.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
