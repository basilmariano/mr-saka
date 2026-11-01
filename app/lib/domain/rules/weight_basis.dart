import '../model/enums.dart';
import '../model/grams.dart';

/// Raised when wet and dry weights would be mixed in one calculation.
///
/// FR-037a: the system "MUST NOT subtract dry kilograms from a fresh harvest weight
/// or the reverse, in any figure it shows the farmer". Making this an exception
/// rather than a silent conversion means the mistake surfaces in tests instead of as
/// a wrong remaining quantity on a farmer's phone.
class WeightBasisMismatch implements Exception {
  const WeightBasisMismatch(this.expected, this.actual);
  final WeightBasis expected;
  final WeightBasis actual;
  @override
  String toString() =>
      'WeightBasisMismatch: cannot combine ${actual.name} with ${expected.name} weight';
}

/// A quantity of produce together with the basis it was weighed on.
class Lot {
  const Lot(this.quantity, this.basis);
  final Grams quantity;
  final WeightBasis basis;

  Lot operator -(Lot other) {
    if (other.basis != basis) throw WeightBasisMismatch(basis, other.basis);
    return Lot(quantity - other.quantity, basis);
  }

  @override
  bool operator ==(Object other) =>
      other is Lot && other.quantity == quantity && other.basis == basis;

  @override
  int get hashCode => Object.hash(quantity, basis);

  @override
  String toString() => '${quantity.formatKg()} kg ${basis.name}';
}

/// Wet and dry weight rules. FR-034a to FR-034d, FR-036, FR-037, FR-037a.
///
/// spec Assumptions, "One weight basis per cropping": a farmer sells a lot either wet
/// or dry, not split between the two, so the basis is declared once per cropping
/// rather than per sale. That is what makes both sides of the subtraction comparable.
abstract final class WeightBasisRules {
  /// FR-034c: the quantity available to sell.
  ///
  /// Sold wet, it is the fresh harvest weight. Sold dry, it is the lot's recorded
  /// dried weight — because drying shrinks the lot, and subtracting dry sales from a
  /// wet harvest would report produce the farmer does not have.
  ///
  /// Returns null when the cropping is sold dry but the dried weight has not been
  /// recorded yet (spec edge case "Basis chosen before the lot is dried").
  static Lot? sellableQuantity({
    required Grams freshHarvest,
    required WeightBasis basis,
    required Grams? driedWeight,
  }) {
    switch (basis) {
      case WeightBasis.wet:
        return Lot(freshHarvest, WeightBasis.wet);
      case WeightBasis.dry:
        if (driedWeight == null) return null;
        return Lot(driedWeight, WeightBasis.dry);
    }
  }

  /// FR-036: remaining unsold quantity, with both sides on the same basis.
  static Lot? remainingQuantity({
    required Lot? sellable,
    required Iterable<Grams> soldQuantities,
  }) {
    if (sellable == null) return null;
    final sold = Grams.sum(soldQuantities);
    return sellable - Lot(sold, sellable.basis);
  }
}

/// Why a sale cannot be recorded. FR-037.
enum SaleRejection {
  /// FR-037: "MUST reject sales on a cropping with no recorded harvest".
  noHarvest,

  /// spec edge case: a dry sale needs the lot's dried weight first.
  driedWeightMissing,

  /// FR-037: quantity exceeds what remains unsold.
  exceedsRemaining,

  /// A sale of zero or a negative quantity is not a sale.
  nonPositiveQuantity,
}

abstract final class SaleRules {
  /// Validates a proposed sale, returning null when it is acceptable.
  static SaleRejection? validate({
    required bool hasHarvest,
    required Lot? sellable,
    required Lot? remaining,
    required Grams quantity,
  }) {
    if (!hasHarvest) return SaleRejection.noHarvest;
    if (quantity.value <= 0) return SaleRejection.nonPositiveQuantity;
    if (sellable == null || remaining == null) {
      return SaleRejection.driedWeightMissing;
    }
    if (quantity > remaining.quantity) return SaleRejection.exceedsRemaining;
    return null;
  }
}
