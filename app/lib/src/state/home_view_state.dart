import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'discovery.dart';
import 'household.dart';
import 'model/household.dart';

part 'home_view_state.g.dart';

sealed class HomeViewState {
  const HomeViewState();
}

class HomeInitialLoading extends HomeViewState {
  const HomeInitialLoading();
}

class HomeDiscoveringWithCache extends HomeViewState {
  const HomeDiscoveringWithCache(this.household);

  final Household household;
}

class HomeDiscoveryFailedNoCache extends HomeViewState {
  const HomeDiscoveryFailedNoCache(this.error);

  final Object error;
}

class HomeDiscoveryFailedWithCache extends HomeViewState {
  const HomeDiscoveryFailedWithCache(this.household, this.error);

  final Household household;
  final Object error;
}

class HomeEmpty extends HomeViewState {
  const HomeEmpty();
}

class HomeReady extends HomeViewState {
  const HomeReady(this.household);

  final Household household;
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

  return HomeReady(household);
}
