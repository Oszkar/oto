// TEMPORARY P0a harness — drives real LAN discovery + the v0.4 event pump
// on a real device so we can confirm the Android debug APK works end-to-end.
// This is NOT the v0.6 UI. Run with:
//   flutter run -t lib/main_p0a.dart -d <device>
// Delete this file when P0a evidence is captured (it is intentionally
// untracked; do not commit).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/rust/frb_generated.dart';
import 'src/state/discovery.dart';
import 'src/state/events.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const ProviderScope(child: _P0aApp()));
}

class _P0aApp extends StatelessWidget {
  const _P0aApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'oto P0a', home: _P0aHome());
  }
}

class _P0aHome extends ConsumerStatefulWidget {
  const _P0aHome();

  @override
  ConsumerState<_P0aHome> createState() => _P0aHomeState();
}

class _P0aHomeState extends ConsumerState<_P0aHome> {
  final List<String> _events = <String>[];

  @override
  Widget build(BuildContext context) {
    final discovery = ref.watch(discoveryProvider);

    // Subscribing keeps the event pump alive; accumulate what arrives.
    ref.listen(changeEventsProvider, (prev, next) {
      next.whenData((e) {
        debugPrint('oto-P0a ChangeEvent: $e');
        setState(() => _events.insert(0, e.toString()));
      });
    });

    return Scaffold(
      appBar: AppBar(title: const Text('oto — P0a smoke')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ref.invalidate(discoveryProvider),
        child: const Icon(Icons.refresh),
      ),
      body: discovery.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('discovering…'),
            ],
          ),
        ),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'discovery FAILED:\n$e',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
        data: (topo) {
          debugPrint(
            'oto-P0a discovered ${topo.speakers.length} speakers / '
            '${topo.groups.length} groups',
          );
          return ListView(
            children: [
              ListTile(
                title: Text(
                  '${topo.speakers.length} speakers, '
                  '${topo.groups.length} groups',
                ),
                subtitle: Text('change events seen: ${_events.length}'),
              ),
              const Divider(),
              for (final s in topo.speakers)
                ListTile(
                  dense: true,
                  title: Text('${s.roomName}  (${s.model ?? 'model: none'})'),
                  subtitle: Text('${s.id}\n${s.ip}'),
                ),
              const Divider(),
              const ListTile(title: Text('— change events (newest first) —')),
              for (final e in _events.take(20))
                ListTile(dense: true, title: Text(e)),
            ],
          );
        },
      ),
    );
  }
}
