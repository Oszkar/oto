// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playback.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One-shot read of a speaker's current volume/mute/transport snapshot.
/// The Rust `speaker_state` SOAP round-trip runs off the UI isolate via FRB.

@ProviderFor(speakerState)
const speakerStateProvider = SpeakerStateFamily._();

/// One-shot read of a speaker's current volume/mute/transport snapshot.
/// The Rust `speaker_state` SOAP round-trip runs off the UI isolate via FRB.

final class SpeakerStateProvider
    extends
        $FunctionalProvider<
          AsyncValue<rust_api.SpeakerStateDto>,
          rust_api.SpeakerStateDto,
          FutureOr<rust_api.SpeakerStateDto>
        >
    with
        $FutureModifier<rust_api.SpeakerStateDto>,
        $FutureProvider<rust_api.SpeakerStateDto> {
  /// One-shot read of a speaker's current volume/mute/transport snapshot.
  /// The Rust `speaker_state` SOAP round-trip runs off the UI isolate via FRB.
  const SpeakerStateProvider._({
    required SpeakerStateFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'speakerStateProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$speakerStateHash();

  @override
  String toString() {
    return r'speakerStateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<rust_api.SpeakerStateDto> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<rust_api.SpeakerStateDto> create(Ref ref) {
    final argument = this.argument as String;
    return speakerState(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SpeakerStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$speakerStateHash() => r'23b8036eb487c907ce8691053f04ec1904435a72';

/// One-shot read of a speaker's current volume/mute/transport snapshot.
/// The Rust `speaker_state` SOAP round-trip runs off the UI isolate via FRB.

final class SpeakerStateFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<rust_api.SpeakerStateDto>, String> {
  const SpeakerStateFamily._()
    : super(
        retry: null,
        name: r'speakerStateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One-shot read of a speaker's current volume/mute/transport snapshot.
  /// The Rust `speaker_state` SOAP round-trip runs off the UI isolate via FRB.

  SpeakerStateProvider call(String speakerId) =>
      SpeakerStateProvider._(argument: speakerId, from: this);

  @override
  String toString() => r'speakerStateProvider';
}

/// Facade for the six transport/volume commands. Methods are thin pass-throughs
/// to the FRB-generated Dart bindings; no state is held here. A real command
/// layer (error handling, optimistic UI) is deferred to v0.6.

@ProviderFor(playbackCommands)
const playbackCommandsProvider = PlaybackCommandsProvider._();

/// Facade for the six transport/volume commands. Methods are thin pass-throughs
/// to the FRB-generated Dart bindings; no state is held here. A real command
/// layer (error handling, optimistic UI) is deferred to v0.6.

final class PlaybackCommandsProvider
    extends
        $FunctionalProvider<
          PlaybackCommands,
          PlaybackCommands,
          PlaybackCommands
        >
    with $Provider<PlaybackCommands> {
  /// Facade for the six transport/volume commands. Methods are thin pass-throughs
  /// to the FRB-generated Dart bindings; no state is held here. A real command
  /// layer (error handling, optimistic UI) is deferred to v0.6.
  const PlaybackCommandsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playbackCommandsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playbackCommandsHash();

  @$internal
  @override
  $ProviderElement<PlaybackCommands> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PlaybackCommands create(Ref ref) {
    return playbackCommands(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlaybackCommands value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlaybackCommands>(value),
    );
  }
}

String _$playbackCommandsHash() => r'f0d2507bc1ce060bc3f0b42861d23628f682bd44';
