import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oto/main.dart';
import 'package:oto/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  testWidgets('greet bridges from Dart through to Rust', (tester) async {
    await tester.pumpWidget(const OtoApp());
    expect(find.textContaining('Rust says: Hello, oto!'), findsOneWidget);
  });
}
