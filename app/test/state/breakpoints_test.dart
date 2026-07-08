import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/breakpoints.dart';

void main() {
  test('width maps to the right tier at the boundaries', () {
    expect(layoutTierForWidth(390), LayoutTier.compact);
    expect(layoutTierForWidth(839.9), LayoutTier.compact);
    expect(layoutTierForWidth(840), LayoutTier.tablet);
    expect(layoutTierForWidth(1199.9), LayoutTier.tablet);
    expect(layoutTierForWidth(1200), LayoutTier.desktop);
    expect(layoutTierForWidth(1920), LayoutTier.desktop);
  });
}
