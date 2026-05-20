/// Thin v0.2 playback bindings; UI is v0.5.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../rust/api.dart' as rust_api;

part 'playback.g.dart';

/// One-shot read of a speaker's current volume/mute/transport snapshot.
/// The Rust `speaker_state` SOAP round-trip runs off the UI isolate via FRB.
@riverpod
Future<rust_api.SpeakerStateDto> speakerState(
  Ref ref,
  String speakerId,
) => rust_api.speakerState(speakerId: speakerId);

/// Facade for the six transport/volume commands. Methods are thin pass-throughs
/// to the FRB-generated Dart bindings; no state is held here. A real command
/// layer (error handling, optimistic UI) is deferred to v0.5.
@riverpod
PlaybackCommands playbackCommands(Ref ref) => const PlaybackCommands();

class PlaybackCommands {
  const PlaybackCommands();

  Future<void> play(String groupId) => rust_api.play(groupId: groupId);

  Future<void> pause(String groupId) => rust_api.pause(groupId: groupId);

  Future<void> next(String groupId) => rust_api.next(groupId: groupId);

  Future<void> previous(String groupId) =>
      rust_api.previous(groupId: groupId);

  Future<void> setVolume(String speakerId, int volume) =>
      rust_api.setVolume(speakerId: speakerId, volume: volume);

  Future<void> setMute(String speakerId, bool muted) =>
      rust_api.setMute(speakerId: speakerId, muted: muted);
}
