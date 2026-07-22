import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'discovery.dart';
import 'household.dart';
import 'model/household.dart';

part 'home_view_state.g.dart';

// Value equality on every case so `homeViewStateProvider` dedupes: without it
// two equal states are `!=` by identity, so the home shell rebuilds on every
// upstream change even when the rendered state is unchanged. `Household` is
// value-comparable (mapEquals), and `error` compares by its own `==`.
sealed class HomeViewState {
  const HomeViewState();
}

class HomeInitialLoading extends HomeViewState {
  const HomeInitialLoading();

  @override
  bool operator ==(Object other) => other is HomeInitialLoading;

  @override
  int get hashCode => (HomeInitialLoading).hashCode;
}

class HomeDiscoveringWithCache extends HomeViewState {
  const HomeDiscoveringWithCache(this.household);

  final Household household;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeDiscoveringWithCache && household == other.household;

  @override
  int get hashCode => household.hashCode;
}

class HomeDiscoveryFailedNoCache extends HomeViewState {
  const HomeDiscoveryFailedNoCache(this.error);

  final Object error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeDiscoveryFailedNoCache && error == other.error;

  @override
  int get hashCode => error.hashCode;
}

class HomeDiscoveryFailedWithCache extends HomeViewState {
  const HomeDiscoveryFailedWithCache(this.household, this.error);

  final Household household;
  final Object error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeDiscoveryFailedWithCache &&
          household == other.household &&
          error == other.error;

  @override
  int get hashCode => Object.hash(household, error);
}

class HomeEmpty extends HomeViewState {
  const HomeEmpty();

  @override
  bool operator ==(Object other) => other is HomeEmpty;

  @override
  int get hashCode => (HomeEmpty).hashCode;
}

class HomeReady extends HomeViewState {
  const HomeReady(this.household);

  final Household household;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeReady && household == other.household;

  @override
  int get hashCode => household.hashCode;
}

/// Cached rooms exist, but every one of them is unreachable.
///
/// Distinct from [HomeReady] so Home can offer a rescan. Discovery itself
/// succeeded - the cached topology is "valid" - so the discovery-error state
/// never fires, and before v0.6.4 that left a user whose whole system had gone
/// quiet with no rescan affordance anywhere on screen.
class HomeAllUnreachable extends HomeViewState {
  const HomeAllUnreachable(this.household);

  final Household household;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeAllUnreachable && household == other.household;

  @override
  int get hashCode => household.hashCode;
}

@riverpod
HomeViewState homeViewState(Ref ref) {
  final discovery = ref.watch(discoveryProvider);
  final isRetryingDiscovery = ref.watch(discoveryRetryingProvider);
  final household = ref.watch(householdProvider);
  final hasCache = household.rooms.isNotEmpty || household.groups.isNotEmpty;

  if (isRetryingDiscovery && discovery.isLoading) {
    return hasCache
        ? HomeDiscoveringWithCache(household)
        : const HomeInitialLoading();
  }

  if (discovery.hasError) {
    final error = discovery.error ?? StateError('Discovery failed');
    return hasCache
        ? HomeDiscoveryFailedWithCache(household, error)
        : HomeDiscoveryFailedNoCache(error);
  }

  if (discovery.isLoading) {
    return hasCache
        ? HomeDiscoveringWithCache(household)
        : const HomeInitialLoading();
  }

  final topology = discovery.hasValue ? discovery.value : null;
  if (topology != null &&
      topology.speakers.isEmpty &&
      topology.groups.isEmpty) {
    return const HomeEmpty();
  }

  // Discovery resolved WITH speakers, but the household reducer hasn't folded
  // them into rooms/groups yet (a transient settle frame between the discovery
  // transition and the reducer running). Don't flash an empty `HomeReady`; keep
  // the loading state until the household has content.
  if (!hasCache) {
    return const HomeInitialLoading();
  }

  // Rooms exist but nothing answers: offer the way out. Checked last so it
  // never pre-empts loading / error / empty, which have their own affordances.
  // `isNotEmpty` is load-bearing: `every` is vacuously true on no rooms, and
  // `hasCache` above passes when only `groups` is populated - so without this a
  // roomless household would claim "no speakers are responding".
  final allUnreachable =
      household.rooms.isNotEmpty &&
      household.rooms.values.every((r) => !r.online);
  return allUnreachable
      ? HomeAllUnreachable(household)
      : HomeReady(household);
}
