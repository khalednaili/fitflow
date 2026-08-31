import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/utils/weight_units.dart';

void main() {
  group('kgToLb / lbToKg', () {
    test('converts kg to lb', () {
      expect(kgToLb(100), closeTo(220.46, 0.01));
    });

    test('converts lb to kg', () {
      expect(lbToKg(220.46), closeTo(100, 0.01));
    });

    test('round-trips within a small tolerance', () {
      expect(lbToKg(kgToLb(83.5)), closeTo(83.5, 1e-9));
    });
  });

  group('convertWeight', () {
    test('returns the same value when units match', () {
      expect(convertWeight(100, 'kg', 'kg'), 100);
      expect(convertWeight(220, 'lbs', 'lbs'), 220);
    });

    test('converts kg to lbs', () {
      expect(convertWeight(100, 'kg', 'lbs'), closeTo(220.46, 0.01));
    });

    test('converts lbs to kg', () {
      expect(convertWeight(220.46, 'lbs', 'kg'), closeTo(100, 0.01));
    });

    test('returns the value unchanged for unrecognised units', () {
      expect(convertWeight(50, 'reps', 'kg'), 50);
    });
  });

  group('roundToPlate', () {
    test('rounds kg to the nearest 2.5', () {
      expect(roundToPlate(101, 'kg'), 100);
      expect(roundToPlate(102, 'kg'), 102.5);
      expect(roundToPlate(103.8, 'kg'), 105);
    });

    test('rounds lbs to the nearest 5', () {
      expect(roundToPlate(222, 'lbs'), 220);
      expect(roundToPlate(223, 'lbs'), 225);
      expect(roundToPlate(227, 'lbs'), 225);
    });
  });
}
