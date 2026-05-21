import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oto/src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const ProviderScope(child: OtoApp()));
}

class OtoApp extends StatelessWidget {
  const OtoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'oto', home: HomePage());
  }
}

/// Neutral placeholder scaffold. Real UI is v0.5.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('oto')),
    );
  }
}
