import '../model/grams.dart';
import '../model/square_metres.dart';

/// Scaling a per-hectare recommendation to a specific field. FR-016.
///
/// This is the arithmetic the app exists to do on the farmer's behalf: SC-004 says
/// the farmer must be able to read off how many 50 kg bags to buy without converting
/// a per-hectare rate themselves.
abstract final class FertilizerCalc {
  /// FR-016: recommended quantity = per-hectare rate x field area.
  ///
  /// 100 kg/ha on 2.5 ha is 250 kg. Exact integer arithmetic throughout: the rate is
  /// grams per hectare and the area is square metres, so dividing by 10,000 converts
  /// square metres to hectares with no rounding until display.
  static Grams recommendedQuantity({
    required Grams ratePerHectare,
    required SquareMetres area,
  }) {
    final product = ratePerHectare.value * area.value;
    return Grams(product ~/ SquareMetres.sqmPerHectare);
  }
}
