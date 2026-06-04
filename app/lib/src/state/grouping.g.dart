// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'grouping.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Facade for the two grouping commands. Thin pass-throughs to the
/// FRB-generated Dart bindings; no state is held here.

@ProviderFor(groupingCommands)
final groupingCommandsProvider = GroupingCommandsProvider._();

/// Facade for the two grouping commands. Thin pass-throughs to the
/// FRB-generated Dart bindings; no state is held here.

final class GroupingCommandsProvider
    extends
        $FunctionalProvider<
          GroupingCommands,
          GroupingCommands,
          GroupingCommands
        >
    with $Provider<GroupingCommands> {
  /// Facade for the two grouping commands. Thin pass-throughs to the
  /// FRB-generated Dart bindings; no state is held here.
  GroupingCommandsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'groupingCommandsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$groupingCommandsHash();

  @$internal
  @override
  $ProviderElement<GroupingCommands> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GroupingCommands create(Ref ref) {
    return groupingCommands(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GroupingCommands value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GroupingCommands>(value),
    );
  }
}

String _$groupingCommandsHash() => r'2ca52ca992b1757ecc697b0a15972eb0f32c6700';
