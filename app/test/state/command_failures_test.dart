import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/rust/api.dart';
import 'package:oto/src/state/command_failures.dart';

void main() {
  group('describeCommandError', () {
    test('network error names the target', () {
      expect(
        describeCommandError(const CommandError.network('x'), 'Kitchen'),
        'Could not reach Kitchen',
      );
    });

    test('not-found error says it is scanning again', () {
      expect(
        describeCommandError(const CommandError.notFound('x'), 'Kitchen'),
        'Kitchen is no longer available - scanning again',
      );
    });

    test('sonos error blames the device, not the network', () {
      expect(
        describeCommandError(const CommandError.sonos('x'), 'Kitchen'),
        'Kitchen rejected that command',
      );
    });

    test('a null label falls back to a generic subject', () {
      expect(
        describeCommandError(const CommandError.network('x'), null),
        'Could not reach that speaker',
      );
    });
  });

  group('CommandFailures', () {
    test('starts with nothing to report', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(commandFailuresProvider), isNull);
    });

    test('report publishes the message', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(commandFailuresProvider.notifier)
          .report('Could not reach Kitchen');

      expect(
        container.read(commandFailuresProvider)?.message,
        'Could not reach Kitchen',
      );
    });

    test('the same message twice is still a new value', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(commandFailuresProvider.notifier);

      notifier.report('Could not reach Kitchen');
      final first = container.read(commandFailuresProvider);
      notifier.report('Could not reach Kitchen');

      expect(
        container.read(commandFailuresProvider),
        isNot(first),
        reason:
            'a listener that dedupes on equality must still fire for a repeat '
            'failure, so each report carries a fresh id',
      );
    });
  });
}
