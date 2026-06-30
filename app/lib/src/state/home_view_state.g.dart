// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_view_state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(homeViewState)
final homeViewStateProvider = HomeViewStateProvider._();

final class HomeViewStateProvider
    extends $FunctionalProvider<HomeViewState, HomeViewState, HomeViewState>
    with $Provider<HomeViewState> {
  HomeViewStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'homeViewStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$homeViewStateHash();

  @$internal
  @override
  $ProviderElement<HomeViewState> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HomeViewState create(Ref ref) {
    return homeViewState(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HomeViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HomeViewState>(value),
    );
  }
}

String _$homeViewStateHash() => r'128d921e587a2a5abc9010e157170b618f3f1568';
