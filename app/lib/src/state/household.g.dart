// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'household.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(HouseholdNotifier)
final householdProvider = HouseholdNotifierProvider._();

final class HouseholdNotifierProvider
    extends $NotifierProvider<HouseholdNotifier, Household> {
  HouseholdNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'householdProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$householdNotifierHash();

  @$internal
  @override
  HouseholdNotifier create() => HouseholdNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Household value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Household>(value),
    );
  }
}

String _$householdNotifierHash() => r'063d56ce940f8628a8003aa11a96b17e69e9a84e';

abstract class _$HouseholdNotifier extends $Notifier<Household> {
  Household build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<Household, Household>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Household, Household>,
              Household,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
