// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'commands.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The FRB command indirection. Overridden in tests with a spy.

@ProviderFor(commandApi)
final commandApiProvider = CommandApiProvider._();

/// The FRB command indirection. Overridden in tests with a spy.

final class CommandApiProvider
    extends $FunctionalProvider<CommandApi, CommandApi, CommandApi>
    with $Provider<CommandApi> {
  /// The FRB command indirection. Overridden in tests with a spy.
  CommandApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'commandApiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$commandApiHash();

  @$internal
  @override
  $ProviderElement<CommandApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CommandApi create(Ref ref) {
    return commandApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CommandApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CommandApi>(value),
    );
  }
}

String _$commandApiHash() => r'8954bdfca071e91312997201470a379b53c45e94';

/// Stable singleton controller; keepAlive so throttle timers + rollback anchors
/// survive across a drag gesture (and the controller isn't rebuilt mid-gesture).

@ProviderFor(playbackController)
final playbackControllerProvider = PlaybackControllerProvider._();

/// Stable singleton controller; keepAlive so throttle timers + rollback anchors
/// survive across a drag gesture (and the controller isn't rebuilt mid-gesture).

final class PlaybackControllerProvider
    extends
        $FunctionalProvider<
          PlaybackController,
          PlaybackController,
          PlaybackController
        >
    with $Provider<PlaybackController> {
  /// Stable singleton controller; keepAlive so throttle timers + rollback anchors
  /// survive across a drag gesture (and the controller isn't rebuilt mid-gesture).
  PlaybackControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playbackControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playbackControllerHash();

  @$internal
  @override
  $ProviderElement<PlaybackController> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PlaybackController create(Ref ref) {
    return playbackController(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlaybackController value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlaybackController>(value),
    );
  }
}

String _$playbackControllerHash() =>
    r'2f45ef8603ea5c5dd63b2b32e8b4da770b74f562';

/// Stable singleton controller; keepAlive for the same reason as
/// [playbackControllerProvider].

@ProviderFor(groupingController)
final groupingControllerProvider = GroupingControllerProvider._();

/// Stable singleton controller; keepAlive for the same reason as
/// [playbackControllerProvider].

final class GroupingControllerProvider
    extends
        $FunctionalProvider<
          GroupingController,
          GroupingController,
          GroupingController
        >
    with $Provider<GroupingController> {
  /// Stable singleton controller; keepAlive for the same reason as
  /// [playbackControllerProvider].
  GroupingControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'groupingControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$groupingControllerHash();

  @$internal
  @override
  $ProviderElement<GroupingController> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  GroupingController create(Ref ref) {
    return groupingController(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GroupingController value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GroupingController>(value),
    );
  }
}

String _$groupingControllerHash() =>
    r'ccad947875d0247609c04eaf15788f458936f901';
