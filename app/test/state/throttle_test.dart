import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/throttle.dart';

void main() {
  test('coalesces rapid calls to the latest value within the window', () {
    fakeAsync((async) {
      final sent = <int>[];
      final t = Throttle(const Duration(milliseconds: 150));
      for (var v = 1; v <= 5; v++) {
        t.run(() => sent.add(v));
      }
      async.elapse(const Duration(milliseconds: 150));
      expect(sent, [5], reason: 'only the latest of a burst is sent on the trailing edge');
    });
  });

  test('flush sends the pending value immediately', () {
    fakeAsync((async) {
      final sent = <int>[];
      final t = Throttle(const Duration(milliseconds: 150));
      t.run(() => sent.add(1));
      t.flush();
      expect(sent, [1]);
    });
  });
}
