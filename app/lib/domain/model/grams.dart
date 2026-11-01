import 'decimal_text.dart';

/// A weight, stored exactly as an integer number of grams.
///
/// Grams rather than kilograms because FR-032 allows an average kg per sack that is
/// not a whole number; grams keep that exact without decimals (research.md R5).
class Grams implements Comparable<Grams> {
  const Grams(this.value);

  /// Parses kilogram input such as `"50"` or `"50.5"`.
  factory Grams.parseKg(String text) => Grams(parseScaled(text, 3));

  factory Grams.fromKg(int kg) => Grams(kg * 1000);

  static const Grams zero = Grams(0);

  /// A fertilizer bag. spec Assumptions: "Bags are assumed to be 50 kg".
  static const int bagGrams = 50 * 1000;

  final int value;

  bool get isZero => value == 0;
  bool get isNegative => value < 0;

  Grams operator +(Grams other) => Grams(value + other.value);
  Grams operator -(Grams other) => Grams(value - other.value);
  Grams operator *(int factor) => Grams(value * factor);
  bool operator >(Grams other) => value > other.value;
  bool operator <(Grams other) => value < other.value;
  bool operator >=(Grams other) => value >= other.value;
  bool operator <=(Grams other) => value <= other.value;

  static Grams sum(Iterable<Grams> weights) {
    var total = 0;
    for (final weight in weights) {
      total += weight.value;
    }
    return Grams(total);
  }

  /// Kilograms scaled by 1000 (exact, no rounding).
  int get kgScaled3 => value;

  /// Tons scaled by 100, rounded half-up. 1 ton = 1,000,000 g (FR-033).
  int get tonsScaled2 => roundedDiv(value, 10000);

  /// Number of 50 kg bags, scaled by 10 so one decimal place is kept (FR-016).
  /// The spec shows partial bags deliberately: 2.5 ha at 100 kg/ha is 5.0 bags, and a
  /// farmer buying fertilizer needs to see 5.5 rather than a rounded 6.
  int get bagsScaled1 => roundedDiv(value * 10, bagGrams);

  /// `"250.0"` kg, one decimal place.
  String formatKg({int decimals = 1}) =>
      withThousandsSeparators(formatScaled(rescale(value, 3, decimals), decimals));

  /// `"5.00"` tons, two decimal places.
  String formatTons() => withThousandsSeparators(formatScaled(tonsScaled2, 2));

  /// `"5.0"` bags, one decimal place.
  String formatBags() => formatScaled(bagsScaled1, 1);

  @override
  int compareTo(Grams other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is Grams && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Grams(${formatKg()} kg)';
}
