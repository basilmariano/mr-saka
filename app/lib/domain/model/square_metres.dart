import 'decimal_text.dart';

/// A field area, stored exactly as an integer number of square metres.
///
/// Square metres rather than hectares because FR-001 allows 2.5 ha and FR-016
/// multiplies area by a per-hectare rate — so an inexact area makes the bag count
/// inexact, and the farmer buys the wrong amount of fertilizer (research.md R5).
class SquareMetres implements Comparable<SquareMetres> {
  const SquareMetres(this.value);

  /// Parses hectare input such as `"2.5"`. Four decimal places of a hectare is one
  /// square metre, which is finer than any farmer will measure.
  factory SquareMetres.parseHectares(String text) =>
      SquareMetres(parseScaled(text, 4));

  static const int sqmPerHectare = 10000;

  final int value;

  /// FR-002: a field area must be greater than zero.
  bool get isValid => value > 0;

  /// Hectares scaled by 100, rounded half-up, for display.
  int get hectaresScaled2 => roundedDiv(value, 100);

  /// `"2.50"` hectares.
  String formatHectares() =>
      withThousandsSeparators(formatScaled(hectaresScaled2, 2));

  @override
  int compareTo(SquareMetres other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is SquareMetres && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'SquareMetres(${formatHectares()} ha)';
}
