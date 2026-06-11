// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'now_playing.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Wall-clock source, injectable for deterministic tests. Defaults to the real
/// clock; only tests override it (production behavior is unchanged).

@ProviderFor(clock)
final clockProvider = ClockProvider._();

/// Wall-clock source, injectable for deterministic tests. Defaults to the real
/// clock; only tests override it (production behavior is unchanged).

final class ClockProvider
    extends
        $FunctionalProvider<
          DateTime Function(),
          DateTime Function(),
          DateTime Function()
        >
    with $Provider<DateTime Function()> {
  /// Wall-clock source, injectable for deterministic tests. Defaults to the real
  /// clock; only tests override it (production behavior is unchanged).
  ClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clockProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clockHash();

  @$internal
  @override
  $ProviderElement<DateTime Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DateTime Function() create(Ref ref) {
    return clock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime Function()>(value),
    );
  }
}

String _$clockHash() => r'3b571c5a0c08b7391c0eed04391003191bab6ccf';

/// A ticking, locally-derived playback position for one group, keyed by
/// `groupId`. Emits the current [Duration] position; recomputes via a ~500 ms
/// timer while playing and freezes otherwise.
///
/// Anchor bookkeeping lives on instance fields and is reconciled in [build]
/// (which re-runs whenever the watched group's `track`/`transport` changes):
///   - `Track` change -> anchor at [Duration.zero], `anchorTime = now`;
///   - non-playing -> playing (no track change) -> anchor at the FROZEN
///     position just computed (never 0), `anchorTime = now`.

@ProviderFor(NowPlayingPosition)
final nowPlayingPositionProvider = NowPlayingPositionFamily._();

/// A ticking, locally-derived playback position for one group, keyed by
/// `groupId`. Emits the current [Duration] position; recomputes via a ~500 ms
/// timer while playing and freezes otherwise.
///
/// Anchor bookkeeping lives on instance fields and is reconciled in [build]
/// (which re-runs whenever the watched group's `track`/`transport` changes):
///   - `Track` change -> anchor at [Duration.zero], `anchorTime = now`;
///   - non-playing -> playing (no track change) -> anchor at the FROZEN
///     position just computed (never 0), `anchorTime = now`.
final class NowPlayingPositionProvider
    extends $NotifierProvider<NowPlayingPosition, Duration> {
  /// A ticking, locally-derived playback position for one group, keyed by
  /// `groupId`. Emits the current [Duration] position; recomputes via a ~500 ms
  /// timer while playing and freezes otherwise.
  ///
  /// Anchor bookkeeping lives on instance fields and is reconciled in [build]
  /// (which re-runs whenever the watched group's `track`/`transport` changes):
  ///   - `Track` change -> anchor at [Duration.zero], `anchorTime = now`;
  ///   - non-playing -> playing (no track change) -> anchor at the FROZEN
  ///     position just computed (never 0), `anchorTime = now`.
  NowPlayingPositionProvider._({
    required NowPlayingPositionFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'nowPlayingPositionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$nowPlayingPositionHash();

  @override
  String toString() {
    return r'nowPlayingPositionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  NowPlayingPosition create() => NowPlayingPosition();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Duration value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Duration>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NowPlayingPositionProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$nowPlayingPositionHash() =>
    r'e9df99d4da0a6df31e90847097a5090949975a3b';

/// A ticking, locally-derived playback position for one group, keyed by
/// `groupId`. Emits the current [Duration] position; recomputes via a ~500 ms
/// timer while playing and freezes otherwise.
///
/// Anchor bookkeeping lives on instance fields and is reconciled in [build]
/// (which re-runs whenever the watched group's `track`/`transport` changes):
///   - `Track` change -> anchor at [Duration.zero], `anchorTime = now`;
///   - non-playing -> playing (no track change) -> anchor at the FROZEN
///     position just computed (never 0), `anchorTime = now`.

final class NowPlayingPositionFamily extends $Family
    with
        $ClassFamilyOverride<
          NowPlayingPosition,
          Duration,
          Duration,
          Duration,
          String
        > {
  NowPlayingPositionFamily._()
    : super(
        retry: null,
        name: r'nowPlayingPositionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A ticking, locally-derived playback position for one group, keyed by
  /// `groupId`. Emits the current [Duration] position; recomputes via a ~500 ms
  /// timer while playing and freezes otherwise.
  ///
  /// Anchor bookkeeping lives on instance fields and is reconciled in [build]
  /// (which re-runs whenever the watched group's `track`/`transport` changes):
  ///   - `Track` change -> anchor at [Duration.zero], `anchorTime = now`;
  ///   - non-playing -> playing (no track change) -> anchor at the FROZEN
  ///     position just computed (never 0), `anchorTime = now`.

  NowPlayingPositionProvider call(String groupId) =>
      NowPlayingPositionProvider._(argument: groupId, from: this);

  @override
  String toString() => r'nowPlayingPositionProvider';
}

/// A ticking, locally-derived playback position for one group, keyed by
/// `groupId`. Emits the current [Duration] position; recomputes via a ~500 ms
/// timer while playing and freezes otherwise.
///
/// Anchor bookkeeping lives on instance fields and is reconciled in [build]
/// (which re-runs whenever the watched group's `track`/`transport` changes):
///   - `Track` change -> anchor at [Duration.zero], `anchorTime = now`;
///   - non-playing -> playing (no track change) -> anchor at the FROZEN
///     position just computed (never 0), `anchorTime = now`.

abstract class _$NowPlayingPosition extends $Notifier<Duration> {
  late final _$args = ref.$arg as String;
  String get groupId => _$args;

  Duration build(String groupId);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<Duration, Duration>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Duration, Duration>,
              Duration,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}
