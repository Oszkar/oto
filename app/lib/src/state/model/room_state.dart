/// View-model room (speaker) type and its physical kind. Immutable,
/// value-comparable. Mapped from backend topology/state by Task 3's reducer.
library;

/// Coarse physical kind of a room's speaker, derived from its model name.
/// Drives UI affordances (e.g. soundbars get TV/HT controls later).
enum RoomKind { speaker, soundbar }

/// Model-name substrings that identify a soundbar/home-theatre device.
/// Matched case-insensitively against the reported model.
const List<String> _soundbarMarkers = [
  'beam',
  'arc',
  'ray',
  'playbar',
  'playbase',
];

/// Classify a device by its model name. Returns [RoomKind.soundbar] when the
/// (lowercased) model contains any known soundbar marker; otherwise
/// [RoomKind.speaker]. A null/unknown model is treated as a plain speaker.
RoomKind roomKindFromModel(String? model) {
  if (model == null) return RoomKind.speaker;
  final lower = model.toLowerCase();
  for (final marker in _soundbarMarkers) {
    if (lower.contains(marker)) return RoomKind.soundbar;
  }
  return RoomKind.speaker;
}

/// One room (a single Sonos speaker) and its current live state.
///
/// All fields are scalar, so [Object.hash] gives a correct value-based hash
/// and equality compares every field by value.
class RoomState {
  final String id;
  final String name;
  final String? model;
  final RoomKind kind;
  final int? volume;
  final bool? muted;
  final bool online;
  final String? groupId;

  const RoomState({
    required this.id,
    required this.name,
    this.model,
    required this.kind,
    this.volume,
    this.muted,
    this.online = true,
    this.groupId,
  });

  /// Sentinel for [copyWith] so a nullable field can be explicitly cleared to
  /// `null`. The `x ?? this.x` idiom can only set-or-keep, never clear; the
  /// optimistic-command rollback needs to restore a cold-start `null` (a value
  /// the field had before the user's drag), which a plain `copyWith` can't
  /// express. Non-nullable fields keep the simple `?? this.x` form.
  static const Object _unset = Object();

  RoomState copyWith({
    String? id,
    String? name,
    Object? model = _unset,
    RoomKind? kind,
    Object? volume = _unset,
    Object? muted = _unset,
    bool? online,
    Object? groupId = _unset,
  }) => RoomState(
    id: id ?? this.id,
    name: name ?? this.name,
    model: identical(model, _unset) ? this.model : model as String?,
    kind: kind ?? this.kind,
    volume: identical(volume, _unset) ? this.volume : volume as int?,
    muted: identical(muted, _unset) ? this.muted : muted as bool?,
    online: online ?? this.online,
    groupId: identical(groupId, _unset) ? this.groupId : groupId as String?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomState &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          model == other.model &&
          kind == other.kind &&
          volume == other.volume &&
          muted == other.muted &&
          online == other.online &&
          groupId == other.groupId;

  @override
  int get hashCode =>
      Object.hash(id, name, model, kind, volume, muted, online, groupId);
}
