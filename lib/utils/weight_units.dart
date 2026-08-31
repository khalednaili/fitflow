/// Helpers for converting and rounding weights between kilograms and pounds.
library;

/// 1 kg in pounds.
const double kgToLbFactor = 2.2046226218;

double kgToLb(double kg) => kg * kgToLbFactor;

double lbToKg(double lb) => lb / kgToLbFactor;

/// Converts [value] expressed in [fromUnit] to [toUnit].
/// Units must be one of 'kg' or 'lbs'. Returns [value] unchanged if the
/// units are equal or not a recognised weight unit.
double convertWeight(double value, String fromUnit, String toUnit) {
  if (fromUnit == toUnit) return value;
  if (fromUnit == 'kg' && toUnit == 'lbs') return kgToLb(value);
  if (fromUnit == 'lbs' && toUnit == 'kg') return lbToKg(value);
  return value;
}

/// Rounds [value] to the nearest practical plate increment for [unit]:
/// 2.5 kg or 5 lb — the smallest common plate increment used in most gyms.
double roundToPlate(double value, String unit) {
  final step = unit == 'lbs' ? 5.0 : 2.5;
  return (value / step).round() * step;
}
