/// Derived list of active sources for the UI. Recomputes whenever the
/// accumulating household changes; the pure derivation lives in `source.dart`.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'household.dart';
import 'model/source.dart';

part 'sources.g.dart';

@riverpod
List<Source> sources(Ref ref) =>
    sourcesFromHousehold(ref.watch(householdProvider));
