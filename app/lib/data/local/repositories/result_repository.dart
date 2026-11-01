import '../../../domain/calc/money_calc.dart';
import '../../../domain/calc/yield_calc.dart';
import '../../../domain/model/centavos.dart';
import '../../../domain/model/entities.dart';
import '../../../domain/model/enums.dart';
import '../../../domain/model/grams.dart';
import '../../../domain/model/square_metres.dart';
import '../../../domain/rules/weight_basis.dart';
import 'expense_repository.dart';
import 'harvest_repository.dart';
import 'sale_repository.dart';

/// Everything the result screen shows for one cropping. FR-039 to FR-042b.
class CroppingResult {
  const CroppingResult({
    required this.state,
    required this.totalExpenses,
    required this.revenue,
    required this.netProfit,
    required this.harvested,
    required this.tonsScaled2,
    required this.tonsPerHectareScaled2,
    required this.costPerKg,
    required this.remaining,
    required this.breakdown,
  });

  /// FR-042, FR-042a, FR-042b: in progress, provisional, or final.
  final ResultState state;

  final Centavos totalExpenses;
  final Centavos revenue;
  final Centavos netProfit;

  /// Fresh weight. Null before a harvest is recorded.
  final Grams? harvested;
  final int? tonsScaled2;
  final int? tonsPerHectareScaled2;

  /// FR-041: null means "not applicable", shown when nothing was harvested.
  final Centavos? costPerKg;

  final Lot? remaining;
  final List<CategoryShare> breakdown;

  /// FR-042: before harvest the absence of revenue is not a loss.
  bool get showsProfit => state != ResultState.inProgress;
}

/// Assembles a cropping's result from its parts.
///
/// Every figure is computed here, on the device, from the local database — which is
/// what lets the result screen work offline and what makes the client the authority
/// on calculation (plan.md).
class ResultRepository {
  ResultRepository({
    required this.expenses,
    required this.harvests,
    required this.sales,
  });

  final ExpenseRepository expenses;
  final HarvestRepository harvests;
  final SaleRepository sales;

  Future<CroppingResult> forCropping({
    required CroppingEntity cropping,
    required SquareMetres area,
  }) async {
    final totalExpenses = await expenses.total(cropping.id);
    final breakdown = await expenses.breakdown(cropping.id);
    final harvest = await harvests.forCropping(cropping.id);
    final revenue = await sales.revenue(cropping.id);
    final remaining = await sales.remaining(cropping);

    final state = switch (cropping.status) {
      CroppingStatus.planted || CroppingStatus.growing => ResultState.inProgress,
      CroppingStatus.harvested => ResultState.provisional,
      CroppingStatus.closed => ResultState.isFinal,
    };

    return CroppingResult(
      state: state,
      totalExpenses: totalExpenses,
      revenue: revenue,
      netProfit: MoneyCalc.netProfit(revenue: revenue, expenses: totalExpenses),
      harvested: harvest?.totalWet,
      tonsScaled2:
          harvest == null ? null : YieldCalc.tonsScaled2(harvest.totalWet),
      tonsPerHectareScaled2: harvest == null
          ? null
          : YieldCalc.tonsPerHectareScaled2(
              harvest: harvest.totalWet,
              area: area,
            ),
      costPerKg: harvest == null
          ? null
          : MoneyCalc.costPerKg(
              totalExpenses: totalExpenses,
              harvested: harvest.totalWet,
            ),
      remaining: remaining,
      breakdown: breakdown,
    );
  }
}
