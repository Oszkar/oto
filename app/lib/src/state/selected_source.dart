/// The user's explicit pick of which source (group id) the wide detail pane
/// shows, plus the resolved id (default + stale fallback) that the pane
/// actually renders. Backs the responsive three-pane layout's detail column.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'household.dart';
import 'sources.dart';

part 'selected_source.g.dart';

/// The user's explicit pick of which source (group id) the wide detail pane
/// shows. Null means "auto" - resolve to the first active source.
@riverpod
class SelectedSource extends _$SelectedSource {
  @override
  String? build() => null;

  void select(String groupId) => state = groupId;
  void clear() => state = null;
}

/// The group id the detail pane should render, applying default + fallback:
/// the explicit selection if that group still exists; else the first active
/// source; else null (empty pane). Watching `household.groups` makes the
/// selection self-heal after a regroup drops the chosen id.
@riverpod
String? resolvedSource(Ref ref) {
  final explicit = ref.watch(selectedSourceProvider);
  final groups = ref.watch(householdProvider.select((h) => h.groups));
  if (explicit != null && groups.containsKey(explicit)) return explicit;
  final sources = ref.watch(sourcesProvider);
  return sources.isEmpty ? null : sources.first.id;
}
