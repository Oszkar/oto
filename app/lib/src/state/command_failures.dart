/// The command-failure notice channel.
///
/// `_Reconciling.send` (commands.dart) rolls back a failed optimistic command
/// and, before v0.6.4, said nothing - so the control silently bounced back with
/// no explanation. It now reports here, and the shell's
/// `CommandFailureListener` renders the notice as a SnackBar.
///
/// The message is derived from the error VARIANT, so the app only ever claims
/// what it actually knows: a network error means unreachable, a Sonos fault
/// means the device refused, a stale id means the topology moved.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../rust/api.dart';

part 'command_failures.g.dart';

/// One failure worth telling the user about. [id] is monotonic so two
/// identical messages are still distinct values - a listener that dedupes on
/// equality must still fire for a repeat failure.
class CommandFailure {
  const CommandFailure({required this.id, required this.message});

  final int id;
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommandFailure && id == other.id && message == other.message;

  @override
  int get hashCode => Object.hash(id, message);
}

/// The user-facing sentence for [e], naming [label] (a room or group name)
/// when the caller knows it.
String describeCommandError(CommandError e, String? label) {
  final who = label ?? 'that speaker';
  return switch (e) {
    CommandError_Network() => 'Could not reach $who',
    CommandError_NotFound() => '$who is no longer available - scanning again',
    CommandError_Sonos() => '$who rejected that command',
  };
}

/// The latest command failure, or null before the first one.
///
/// `keepAlive`: failures are reported from controllers that outlive any single
/// widget, so the channel must not be torn down between them.
///
/// This is a latest-value channel, not a queue: the delivered value is never
/// cleared, and consumers are edge-triggered (`ref.listen`, not
/// `fireImmediately`). That is only correct because the sole consumer -
/// `CommandFailureListener` - is mounted for the whole app lifetime, so there
/// is no window in which a report has no listener. See that widget's doc
/// comment before changing either half.
@Riverpod(keepAlive: true)
class CommandFailures extends _$CommandFailures {
  int _seq = 0;

  @override
  CommandFailure? build() => null;

  void report(String message) {
    state = CommandFailure(id: ++_seq, message: message);
  }
}
