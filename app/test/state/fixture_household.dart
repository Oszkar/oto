import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/model/household.dart';

/// A [HouseholdNotifier] that yields a fixed [Household], for overriding
/// `householdProvider` in state-layer tests without discovery or events.
class FixtureHousehold extends HouseholdNotifier {
  FixtureHousehold(this._household);

  final Household _household;

  @override
  Household build() => _household;
}
