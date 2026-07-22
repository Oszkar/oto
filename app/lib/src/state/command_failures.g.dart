// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'command_failures.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The latest command failure, or null before the first one.
///
/// `keepAlive`: failures are reported from controllers that outlive any single
/// widget, so the channel must not be torn down between them.
///
/// This is a latest-value channel, not a queue: the delivered value is never
/// cleared, and consumers are edge-triggered (`ref.listen`, not
/// `fireImmediately`). That is only correct because the sole consumer -
/// `CommandFailureListener` - is mounted for the whole app lifetime, so there
/// is no window in which a report has no listener. See that widget's doc
/// comment before changing either half.

@ProviderFor(CommandFailures)
final commandFailuresProvider = CommandFailuresProvider._();

/// The latest command failure, or null before the first one.
///
/// `keepAlive`: failures are reported from controllers that outlive any single
/// widget, so the channel must not be torn down between them.
///
/// This is a latest-value channel, not a queue: the delivered value is never
/// cleared, and consumers are edge-triggered (`ref.listen`, not
/// `fireImmediately`). That is only correct because the sole consumer -
/// `CommandFailureListener` - is mounted for the whole app lifetime, so there
/// is no window in which a report has no listener. See that widget's doc
/// comment before changing either half.
final class CommandFailuresProvider
    extends $NotifierProvider<CommandFailures, CommandFailure?> {
  /// The latest command failure, or null before the first one.
  ///
  /// `keepAlive`: failures are reported from controllers that outlive any single
  /// widget, so the channel must not be torn down between them.
  ///
  /// This is a latest-value channel, not a queue: the delivered value is never
  /// cleared, and consumers are edge-triggered (`ref.listen`, not
  /// `fireImmediately`). That is only correct because the sole consumer -
  /// `CommandFailureListener` - is mounted for the whole app lifetime, so there
  /// is no window in which a report has no listener. See that widget's doc
  /// comment before changing either half.
  CommandFailuresProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'commandFailuresProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$commandFailuresHash();

  @$internal
  @override
  CommandFailures create() => CommandFailures();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CommandFailure? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CommandFailure?>(value),
    );
  }
}

String _$commandFailuresHash() => r'd18bc8f4a6d1c70e723f15a4ff15332fb35d3348';

/// The latest command failure, or null before the first one.
///
/// `keepAlive`: failures are reported from controllers that outlive any single
/// widget, so the channel must not be torn down between them.
///
/// This is a latest-value channel, not a queue: the delivered value is never
/// cleared, and consumers are edge-triggered (`ref.listen`, not
/// `fireImmediately`). That is only correct because the sole consumer -
/// `CommandFailureListener` - is mounted for the whole app lifetime, so there
/// is no window in which a report has no listener. See that widget's doc
/// comment before changing either half.

abstract class _$CommandFailures extends $Notifier<CommandFailure?> {
  CommandFailure? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<CommandFailure?, CommandFailure?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CommandFailure?, CommandFailure?>,
              CommandFailure?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
