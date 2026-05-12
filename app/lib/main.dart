import 'package:flutter/material.dart';
import 'package:oto/src/rust/api.dart';
import 'package:oto/src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const OtoApp());
}

class OtoApp extends StatelessWidget {
  const OtoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'oto',
      home: Scaffold(
        appBar: AppBar(title: const Text('oto — scaffold')),
        body: Center(
          child: Text('Rust says: ${greet(name: "oto")}'),
        ),
      ),
    );
  }
}
