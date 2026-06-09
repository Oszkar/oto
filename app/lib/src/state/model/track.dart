/// View-model track type. Immutable, value-comparable. Mapped from the
/// backend `TrackDto` via [Track.fromDto]; the UI works only in this type.
library;

import '../../rust/api.dart' show TrackDto;

/// Now-playing metadata for a group's current track.
///
/// All fields are scalar, so [Object.hash] over them gives a correct
/// value-based hash; equality is by-value across every field.
class Track {
  final String? id;
  final String? title;
  final String? artist;
  final String? album;
  final int? trackNumber;
  final Duration? duration;
  final String? artUri;
  final String? uri;

  const Track({
    this.id,
    this.title,
    this.artist,
    this.album,
    this.trackNumber,
    this.duration,
    this.artUri,
    this.uri,
  });

  /// Map the backend DTO to the view type. `durationSecs` (`BigInt?`)
  /// becomes a `Duration?`.
  factory Track.fromDto(TrackDto d) => Track(
    id: d.id,
    title: d.title,
    artist: d.artist,
    album: d.album,
    artUri: d.artUri,
    uri: d.uri,
    trackNumber: d.trackNumber,
    duration: d.durationSecs == null
        ? null
        : Duration(seconds: d.durationSecs!.toInt()),
  );

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    int? trackNumber,
    Duration? duration,
    String? artUri,
    String? uri,
  }) => Track(
    id: id ?? this.id,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    trackNumber: trackNumber ?? this.trackNumber,
    duration: duration ?? this.duration,
    artUri: artUri ?? this.artUri,
    uri: uri ?? this.uri,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          artist == other.artist &&
          album == other.album &&
          trackNumber == other.trackNumber &&
          duration == other.duration &&
          artUri == other.artUri &&
          uri == other.uri;

  @override
  int get hashCode =>
      Object.hash(id, title, artist, album, trackNumber, duration, artUri, uri);
}
