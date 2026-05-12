import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oto/src/rust/frb_generated.dart';
import 'package:oto/src/state/greeting.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const ProviderScope(child: OtoApp()));
}

class OtoApp extends StatelessWidget {
  const OtoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'oto',
      home: HomePage(),
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final greeting = ref.watch(greetingProvider(name: 'oto'));
    return Scaffold(
      appBar: AppBar(title: const Text('oto — scaffold')),
      body: Center(child: Text('Rust says: $greeting')),
    );
  }
}
