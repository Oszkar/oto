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
/// widget, and the shell listener must not miss one because no widget happened
/// to be watching.

@ProviderFor(CommandFailures)
final commandFailuresProvider = CommandFailuresProvider._();

/// The latest command failure, or null before the first one.
///
/// `keepAlive`: failures are reported from controllers that outlive any single
/// widget, and the shell listener must not miss one because no widget happened
/// to be watching.
final class CommandFailuresProvider
    extends $NotifierProvider<CommandFailures, CommandFailure?> {
  /// The latest command failure, or null before the first one.
  ///
  /// `keepAlive`: failures are reported from controllers that outlive any single
  /// widget, and the shell listener must not miss one because no widget happened
  /// to be watching.
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
/// widget, and the shell listener must not miss one because no widget happened
/// to be watching.

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
