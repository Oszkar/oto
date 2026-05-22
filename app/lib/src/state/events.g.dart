// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Single-consumer stream of ChangeEvents from Rust. Subscribes once
/// per discovery cycle: when `discoveryProvider` yields a new value
/// (success or error), this provider is invalidated and re-runs the
/// FRB `subscribe_change_events` call against the current wire.
///
/// Per-speaker / per-group projections are added in Slice 2; for
/// v0.4 baseline, downstream consumers `ref.watch(changeEventsProvider)`
/// directly and filter client-side.

@ProviderFor(changeEvents)
const changeEventsProvider = ChangeEventsProvider._();

/// Single-consumer stream of ChangeEvents from Rust. Subscribes once
/// per discovery cycle: when `discoveryProvider` yields a new value
/// (success or error), this provider is invalidated and re-runs the
/// FRB `subscribe_change_events` call against the current wire.
///
/// Per-speaker / per-group projections are added in Slice 2; for
/// v0.4 baseline, downstream consumers `ref.watch(changeEventsProvider)`
/// directly and filter client-side.

final class ChangeEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<rust_api.ChangeEventDto>,
          rust_api.ChangeEventDto,
          Stream<rust_api.ChangeEventDto>
        >
    with
        $FutureModifier<rust_api.ChangeEventDto>,
        $StreamProvider<rust_api.ChangeEventDto> {
  /// Single-consumer stream of ChangeEvents from Rust. Subscribes once
  /// per discovery cycle: when `discoveryProvider` yields a new value
  /// (success or error), this provider is invalidated and re-runs the
  /// FRB `subscribe_change_events` call against the current wire.
  ///
  /// Per-speaker / per-group projections are added in Slice 2; for
  /// v0.4 baseline, downstream consumers `ref.watch(changeEventsProvider)`
  /// directly and filter client-side.
  const ChangeEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'changeEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$changeEventsHash();

  @$internal
  @override
  $StreamProviderElement<rust_api.ChangeEventDto> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<rust_api.ChangeEventDto> create(Ref ref) {
    return changeEvents(ref);
  }
}

String _$changeEventsHash() => r'344da31f15d411d6cab6a6b3b736f511e0a9da06';
