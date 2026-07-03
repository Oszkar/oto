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

String _$homeViewStateHash() => r'ce27dd1ae438875e19d61959f7672c34dd9b085f';
