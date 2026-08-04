// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'selected_source.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Tracks the coordinator the wide detail pane shows, reconciling on every
/// active-source change (finding: a plain "first active source" default jumps
/// whenever another room starts/stops).
///
/// `keepAlive`: this holds explicit user intent, and on compact width NOTHING
/// watches it - `OtoScaffold` skips the detail pane below 840, and
/// `group_card.dart` short-circuits its `ref.watch` behind `wide &&`. Under
/// autoDispose that made `nav.dart`'s `select()` write into a provider disposed
/// on the next tick, so a wide -> compact -> wide resize silently dropped the
/// pin. The state is two small fields for the app's lifetime.

@ProviderFor(SelectedSource)
final selectedSourceProvider = SelectedSourceProvider._();

/// Tracks the coordinator the wide detail pane shows, reconciling on every
/// active-source change (finding: a plain "first active source" default jumps
/// whenever another room starts/stops).
///
/// `keepAlive`: this holds explicit user intent, and on compact width NOTHING
/// watches it - `OtoScaffold` skips the detail pane below 840, and
/// `group_card.dart` short-circuits its `ref.watch` behind `wide &&`. Under
/// autoDispose that made `nav.dart`'s `select()` write into a provider disposed
/// on the next tick, so a wide -> compact -> wide resize silently dropped the
/// pin. The state is two small fields for the app's lifetime.
final class SelectedSourceProvider
    extends $NotifierProvider<SelectedSource, PaneSource> {
  /// Tracks the coordinator the wide detail pane shows, reconciling on every
  /// active-source change (finding: a plain "first active source" default jumps
  /// whenever another room starts/stops).
  ///
  /// `keepAlive`: this holds explicit user intent, and on compact width NOTHING
  /// watches it - `OtoScaffold` skips the detail pane below 840, and
  /// `group_card.dart` short-circuits its `ref.watch` behind `wide &&`. Under
  /// autoDispose that made `nav.dart`'s `select()` write into a provider disposed
  /// on the next tick, so a wide -> compact -> wide resize silently dropped the
  /// pin. The state is two small fields for the app's lifetime.
  SelectedSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedSourceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedSourceHash();

  @$internal
  @override
  SelectedSource create() => SelectedSource();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PaneSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PaneSource>(value),
    );
  }
}

String _$selectedSourceHash() => r'2cdea3238103ca44ff8be8ad9b3b63503e4e3aed';

/// Tracks the coordinator the wide detail pane shows, reconciling on every
/// active-source change (finding: a plain "first active source" default jumps
/// whenever another room starts/stops).
///
/// `keepAlive`: this holds explicit user intent, and on compact width NOTHING
/// watches it - `OtoScaffold` skips the detail pane below 840, and
/// `group_card.dart` short-circuits its `ref.watch` behind `wide &&`. Under
/// autoDispose that made `nav.dart`'s `select()` write into a provider disposed
/// on the next tick, so a wide -> compact -> wide resize silently dropped the
/// pin. The state is two small fields for the app's lifetime.

abstract class _$SelectedSource extends $Notifier<PaneSource> {
  PaneSource build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<PaneSource, PaneSource>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PaneSource, PaneSource>,
              PaneSource,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The group id the detail pane should render: the tracked coordinator mapped
/// to its CURRENT group (active or idle, so a regroup or an idle explicit pin
/// still resolves), else the first active source, else null (empty pane).
///
/// The coordinator -> group-id mapping is done inside a `select` so this only
/// recomputes when that id (or the active-source list) actually changes, not on
/// every unrelated group event that rebuilds the `groups` map.

@ProviderFor(resolvedSource)
final resolvedSourceProvider = ResolvedSourceProvider._();

/// The group id the detail pane should render: the tracked coordinator mapped
/// to its CURRENT group (active or idle, so a regroup or an idle explicit pin
/// still resolves), else the first active source, else null (empty pane).
///
/// The coordinator -> group-id mapping is done inside a `select` so this only
/// recomputes when that id (or the active-source list) actually changes, not on
/// every unrelated group event that rebuilds the `groups` map.

final class ResolvedSourceProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// The group id the detail pane should render: the tracked coordinator mapped
  /// to its CURRENT group (active or idle, so a regroup or an idle explicit pin
  /// still resolves), else the first active source, else null (empty pane).
  ///
  /// The coordinator -> group-id mapping is done inside a `select` so this only
  /// recomputes when that id (or the active-source list) actually changes, not on
  /// every unrelated group event that rebuilds the `groups` map.
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

String _$resolvedSourceHash() => r'8f43156a56a5d77c040398c9e003de47c6db90e7';
