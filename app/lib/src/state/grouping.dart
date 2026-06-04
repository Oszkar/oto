/// v0.5.1 group form/break bindings; UI is v0.6.
///
/// Await-only pass-throughs to the FRB-generated bindings. There is **no**
/// refresh trigger here (no `ref.invalidate(discoveryProvider)`): a join/leave
/// fires `GroupMembership` NOTIFYs exactly like a Sonos-app regroup, which the
/// existing debounced `topologyController` already coalesces into one re-pull.
/// A self-triggered immediate re-poll would race the topology settle (the
/// hardware spike on 2026-06-04 confirmed the NOTIFY fires after settle).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../rust/api.dart' as rust_api;

part 'grouping.g.dart';

/// Facade for the two grouping commands. Thin pass-throughs to the
/// FRB-generated Dart bindings; no state is held here.
@riverpod
GroupingCommands groupingCommands(Ref ref) => const GroupingCommands();

class GroupingCommands {
  const GroupingCommands();

  Future<void> joinGroup(String speakerId, String coordinatorId) =>
      rust_api.joinGroup(speakerId: speakerId, coordinatorId: coordinatorId);

  Future<void> leaveGroup(String speakerId) =>
      rust_api.leaveGroup(speakerId: speakerId);
}
