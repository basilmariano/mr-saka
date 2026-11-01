import '../model/centavos.dart';
import '../model/decimal_text.dart';
import '../model/enums.dart';
import '../model/grams.dart';

/// One expense category's contribution to a cropping's total. FR-030.
class CategoryShare {
  const CategoryShare({
    required this.category,
    required this.total,
    required this.percentScaled1,
  });

  final ExpenseCategory category;
  final Centavos total;

  /// Share of the overall total, scaled by 10 (so 149 means 14.9%).
  final int percentScaled1;

  String formatPercent() => '${formatScaled(percentScaled1, 1)}%';
}

/// Money figures for a cropping. FR-029, FR-030, FR-035, FR-040, FR-041.
abstract final class MoneyCalc {
  /// FR-029: running total of expenses.
  static Centavos totalExpenses(Iterable<Centavos> amounts) => Centavos.sum(amounts);

  /// FR-030: breakdown by category with each category's amount and share of total.
  ///
  /// Only categories with recorded expenses appear, ordered by amount descending so
  /// the farmer sees where the money actually went first.
  static List<CategoryShare> categoryBreakdown(
    Map<ExpenseCategory, Centavos> byCategory,
  ) {
    final total = Centavos.sum(byCategory.values);
    final shares = byCategory.entries
        .where((entry) => !entry.value.isZero)
        .map(
          (entry) => CategoryShare(
            category: entry.key,
            total: entry.value,
            percentScaled1: entry.value.percentOfScaled1(total),
          ),
        )
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return shares;
  }

  /// Revenue from one sale: quantity x price per kilogram.
  ///
  /// Quantity is grams and price is centavos per kilogram, so dividing by 1000
  /// converts grams to kilograms. Rounded half-up because a part-gram of a centavo
  /// is not a real amount of money.
  static Centavos saleRevenue({
    required Grams quantity,
    required Centavos pricePerKg,
  }) =>
      Centavos(roundedDiv(quantity.value * pricePerKg.value, 1000));

  /// FR-035: a cropping's revenue is the sum across its sales.
  static Centavos totalRevenue(Iterable<Centavos> saleAmounts) =>
      Centavos.sum(saleAmounts);

  /// FR-040: net profit or loss is revenue minus expenses.
  static Centavos netProfit({
    required Centavos revenue,
    required Centavos expenses,
  }) =>
      revenue - expenses;

  /// FR-040: cost per kilogram produced is total expenses divided by total harvested
  /// kilograms, on the fresh-weight basis — not kilograms sold, so it measures
  /// production efficiency rather than sales performance (spec Assumptions).
  ///
  /// FR-041: returns null, meaning "not applicable", when nothing was harvested.
  /// A total crop failure is a real outcome and must not surface as a division error.
  static Centavos? costPerKg({
    required Centavos totalExpenses,
    required Grams harvested,
  }) {
    if (harvested.value <= 0) return null;
    return Centavos(roundedDiv(totalExpenses.value * 1000, harvested.value));
  }
}
