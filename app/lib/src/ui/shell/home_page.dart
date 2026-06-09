import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'oto_scaffold.dart';

/// Placeholder Home. Task 11b replaces this body with the real HomeScreen.
///
/// Kept a [ConsumerWidget] (even though it reads no providers yet) so the swap
/// in Task 11b is a body-only change. Intentionally depends on no Home widgets.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const OtoScaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
