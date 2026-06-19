// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_editor.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Editor selection, keyed by host room id. Seeds from the host group's current
/// members; `toggle` adds/removes a room (the host stays selected).

@ProviderFor(GroupEditorSelection)
final groupEditorSelectionProvider = GroupEditorSelectionFamily._();

/// Editor selection, keyed by host room id. Seeds from the host group's current
/// members; `toggle` adds/removes a room (the host stays selected).
final class GroupEditorSelectionProvider
    extends $NotifierProvider<GroupEditorSelection, Set<String>> {
  /// Editor selection, keyed by host room id. Seeds from the host group's current
  /// members; `toggle` adds/removes a room (the host stays selected).
  GroupEditorSelectionProvider._({
    required GroupEditorSelectionFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'groupEditorSelectionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$groupEditorSelectionHash();

  @override
  String toString() {
    return r'groupEditorSelectionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  GroupEditorSelection create() => GroupEditorSelection();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GroupEditorSelectionProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$groupEditorSelectionHash() =>
    r'576deec030015ebb769900028a014050f452ef9c';

/// Editor selection, keyed by host room id. Seeds from the host group's current
/// members; `toggle` adds/removes a room (the host stays selected).

final class GroupEditorSelectionFamily extends $Family
    with
        $ClassFamilyOverride<
          GroupEditorSelection,
          Set<String>,
          Set<String>,
          Set<String>,
          String
        > {
  GroupEditorSelectionFamily._()
    : super(
        retry: null,
        name: r'groupEditorSelectionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Editor selection, keyed by host room id. Seeds from the host group's current
  /// members; `toggle` adds/removes a room (the host stays selected).

  GroupEditorSelectionProvider call(String host) =>
      GroupEditorSelectionProvider._(argument: host, from: this);

  @override
  String toString() => r'groupEditorSelectionProvider';
}

/// Editor selection, keyed by host room id. Seeds from the host group's current
/// members; `toggle` adds/removes a room (the host stays selected).

abstract class _$GroupEditorSelection extends $Notifier<Set<String>> {
  late final _$args = ref.$arg as String;
  String get host => _$args;

  Set<String> build(String host);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}
