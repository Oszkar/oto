/// View-model household: the whole topology snapshot — rooms and groups,
/// keyed by id. Immutable, value-comparable. Mapped by Task 3's reducer.
library;

import 'package:flutter/foundation.dart' show mapEquals;

import 'group_state.dart';
import 'room_state.dart';

/// The complete known topology: every room and every group, keyed by id.
///
/// Maps are collection fields, so equality compares them with [mapEquals]
/// and the hash folds entries with [Object.hashAll] to stay value-based.
class Household {
  final Map<String, RoomState> rooms;
  final Map<String, GroupState> groups;

  const Household({this.rooms = const {}, this.groups = const {}});

  Household copyWith({
    Map<String, RoomState>? rooms,
    Map<String, GroupState>? groups,
  }) => Household(rooms: rooms ?? this.rooms, groups: groups ?? this.groups);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Household &&
          runtimeType == other.runtimeType &&
          mapEquals(rooms, other.rooms) &&
          mapEquals(groups, other.groups);

  // Order-independent so it stays consistent with the order-independent
  // `mapEquals` above: equal Households (same entries, any insertion order)
  // must hash equal (codex review, PR #80).
  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      rooms.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      groups.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}
