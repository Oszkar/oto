// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'selected_source.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The user's explicit pick of which source (group id) the wide detail pane
/// shows. Null means "auto" - resolve to the first active source.

@ProviderFor(SelectedSource)
final selectedSourceProvider = SelectedSourceProvider._();

/// The user's explicit pick of which source (group id) the wide detail pane
/// shows. Null means "auto" - resolve to the first active source.
final class SelectedSourceProvider
    extends $NotifierProvider<SelectedSource, String?> {
  /// The user's explicit pick of which source (group id) the wide detail pane
  /// shows. Null means "auto" - resolve to the first active source.
  SelectedSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedSourceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedSourceHash();

  @$internal
  @override
  SelectedSource create() => SelectedSource();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$selectedSourceHash() => r'c0a77b7a78c4244197c5cd0989f0fc60ad44c2df';

/// The user's explicit pick of which source (group id) the wide detail pane
/// shows. Null means "auto" - resolve to the first active source.

abstract class _$SelectedSource extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The group id the detail pane should render, applying default + fallback:
/// the explicit selection if that group still exists; else the first active
/// source; else null (empty pane). Watching `household.groups` makes the
/// selection self-heal after a regroup drops the chosen id.

@ProviderFor(resolvedSource)
final resolvedSourceProvider = ResolvedSourceProvider._();

/// The group id the detail pane should render, applying default + fallback:
/// the explicit selection if that group still exists; else the first active
/// source; else null (empty pane). Watching `household.groups` makes the
/// selection self-heal after a regroup drops the chosen id.

final class ResolvedSourceProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// The group id the detail pane should render, applying default + fallback:
  /// the explicit selection if that group still exists; else the first active
  /// source; else null (empty pane). Watching `household.groups` makes the
  /// selection self-heal after a regroup drops the chosen id.
  ResolvedSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'resolvedSourceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$resolvedSourceHash();

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    return resolvedSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$resolvedSourceHash() => r'e4adbfb943ed5378f622113baf77646b1de3428b';
