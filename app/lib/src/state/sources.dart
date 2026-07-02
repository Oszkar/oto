/// Derived list of active sources for the UI. Recomputes whenever the
/// accumulating household changes; the pure derivation lives in `source.dart`.
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'household.dart';
import 'model/source.dart';

part 'sources.g.dart';

/// Derived active-source list for the UI.
///
/// A class Notifier (not a bare function provider) so [updateShouldNotify] can
/// dedupe by value: [sourcesFromHousehold] returns a fresh `List` on every
/// household delta, and `List` has no value equality, so a plain provider would
/// notify consumers (`bottom_strip`) on *every* event - an unrelated room's
/// volume tick - even when the derived sources are identical. `listEquals` over
/// the value-equal [Source] elements suppresses those no-op rebuilds.
@riverpod
class Sources extends _$Sources {
  @override
  List<Source> build() => sourcesFromHousehold(ref.watch(householdProvider));

  @override
  bool updateShouldNotify(List<Source> previous, List<Source> next) =>
      !listEquals(previous, next);
}
