import '../model/decimal_text.dart';
import '../model/grams.dart';
import '../model/square_metres.dart';

/// Yield figures, always on the fresh-weight basis. FR-033.
///
/// spec Assumptions, "Fresh weight is the yield basis": harvest is always recorded
/// wet, so yield, tons per hectare, and cost per kilogram sit on one consistent basis
/// and are comparable across every cropping (FR-043). The app never converts between
/// wet and dry weight.
abstract final class YieldCalc {
  /// Total harvest in tons, scaled by 100. 1 ton = 1,000,000 g.
  static int tonsScaled2(Grams harvest) => harvest.tonsScaled2;

  /// Yield in tons per hectare, scaled by 100.
  ///
  /// tons/ha = (g / 1e6) / (sqm / 1e4) = g / (100 x sqm), so scaled by 100 this
  /// reduces to g / sqm exactly — 5,000,000 g over 25,000 sqm is 200, i.e. 2.00 t/ha.
  ///
  /// Returns null for a zero area rather than dividing by zero.
  static int? tonsPerHectareScaled2({
    required Grams harvest,
    required SquareMetres area,
  }) {
    if (area.value <= 0) return null;
    return roundedDiv(harvest.value, area.value);
  }

  static String formatTonsPerHectare(int? scaled2) =>
      scaled2 == null ? '-' : formatScaled(scaled2, 2);
}
