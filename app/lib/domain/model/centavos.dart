import 'decimal_text.dart';

/// A peso amount, stored exactly as an integer number of centavos.
///
/// data-model.md: "No raw `int` or `double` crosses a layer boundary for these
/// quantities." Wrapping the integer stops a bare number being passed where a currency
/// was meant, and stops anyone reaching for a `double` (SC-009, research.md R5).
class Centavos implements Comparable<Centavos> {
  const Centavos(this.value);

  /// Parses farmer input such as `"3500"` or `"3,500.50"`.
  factory Centavos.parse(String text) => Centavos(parseScaled(text, 2));

  factory Centavos.fromPesos(int pesos) => Centavos(pesos * 100);

  static const Centavos zero = Centavos(0);

  /// Exact centavos. Never a fraction.
  final int value;

  bool get isZero => value == 0;
  bool get isNegative => value < 0;
  bool get isPositive => value > 0;

  Centavos operator +(Centavos other) => Centavos(value + other.value);
  Centavos operator -(Centavos other) => Centavos(value - other.value);
  Centavos operator -() => Centavos(-value);
  Centavos operator *(int factor) => Centavos(value * factor);
  bool operator >(Centavos other) => value > other.value;
  bool operator <(Centavos other) => value < other.value;
  bool operator >=(Centavos other) => value >= other.value;
  bool operator <=(Centavos other) => value <= other.value;

  static Centavos sum(Iterable<Centavos> amounts) {
    var total = 0;
    for (final amount in amounts) {
      total += amount.value;
    }
    return Centavos(total);
  }

  /// This amount as a percentage of [whole], rounded half-up to one decimal place,
  /// returned scaled by 10 (so `253` means 25.3%). Used for the category breakdown
  /// share in FR-030.
  int percentOfScaled1(Centavos whole) {
    if (whole.isZero) return 0;
    return roundedDiv(value * 1000, whole.value);
  }

  /// `"23,500.00"` — digits only, no currency symbol, so the symbol can be a
  /// localised resource (FR-056).
  String format() => withThousandsSeparators(formatScaled(value, 2));

  /// `"PHP 23,500.00"`. FR-047: all monetary amounts are in Philippine pesos.
  String formatWithSymbol({String symbol = '₱'}) {
    final negative = isNegative;
    final body = withThousandsSeparators(formatScaled(value.abs(), 2));
    return '${negative ? '-' : ''}$symbol$body';
  }

  @override
  int compareTo(Centavos other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is Centavos && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Centavos(${format()})';
}
