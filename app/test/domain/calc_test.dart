import 'package:saka/domain/calc/date_calc.dart';
import 'package:saka/domain/calc/fertilizer_calc.dart';
import 'package:saka/domain/calc/money_calc.dart';
import 'package:saka/domain/calc/yield_calc.dart';
import 'package:saka/domain/model/calendar_date.dart';
import 'package:saka/domain/model/centavos.dart';
import 'package:saka/domain/model/enums.dart';
import 'package:saka/domain/model/grams.dart';
import 'package:saka/domain/model/square_metres.dart';
import 'package:test/test.dart';

/// Every expected value below was computed by hand. SC-009: "Every figure the app
/// reports for a completed cropping matches the farmer's own hand calculation from
/// the same inputs, for 100% of test croppings."
void main() {
  // quickstart.md Scenario 1 fixture.
  final field = SquareMetres.parseHectares('2.5'); // 25,000 sqm
  final harvest = Grams.fromKg(5000); // 100 sacks x 50 kg
  final expenses = Centavos.fromPesos(23500); // 3,500 + 12,000 + 8,000

  group('FertilizerCalc (FR-016)', () {
    test('scales 100 kg/ha to 250 kg on 2.5 ha', () {
      final quantity = FertilizerCalc.recommendedQuantity(
        ratePerHectare: Grams.fromKg(100),
        area: field,
      );
      expect(quantity.formatKg(), '250.0');
      expect(quantity.formatBags(), '5.0');
    });

    test('shows a partial bag rather than rounding up', () {
      // A farmer buying fertilizer needs 5.5, not 6.
      final quantity = FertilizerCalc.recommendedQuantity(
        ratePerHectare: Grams.fromKg(110),
        area: field,
      );
      expect(quantity.formatKg(), '275.0');
      expect(quantity.formatBags(), '5.5');
    });

    test('scales a fractional hectare exactly', () {
      final quantity = FertilizerCalc.recommendedQuantity(
        ratePerHectare: Grams.fromKg(100),
        area: SquareMetres.parseHectares('0.75'),
      );
      expect(quantity.formatKg(), '75.0');
    });
  });

  group('DateCalc (FR-009, FR-017)', () {
    test('a step 14 days after planting on 1 March is due 15 March', () {
      expect(
        DateCalc.applicationDueDate(
          plantingDate: const CalendarDate(2026, 3, 1),
          daysAfterPlanting: 14,
        ),
        const CalendarDate(2026, 3, 15),
      );
    });

    test('derives the expected harvest date from maturity days', () {
      expect(
        DateCalc.expectedHarvestDate(
          plantingDate: const CalendarDate(2026, 3, 1),
          maturityDays: 110,
        ),
        const CalendarDate(2026, 6, 19),
      );
    });

    test('returns null when the variety has no maturity, rather than guessing', () {
      // spec edge case "Variety with unknown maturity": the farmer is asked instead.
      expect(
        DateCalc.expectedHarvestDate(
          plantingDate: const CalendarDate(2026, 3, 1),
          maturityDays: null,
        ),
        isNull,
      );
    });
  });

  group('YieldCalc (FR-033)', () {
    test('5,000 kg is 5.00 tons', () {
      expect(YieldCalc.tonsScaled2(harvest), 500);
      expect(harvest.formatTons(), '5.00');
    });

    test('5,000 kg on 2.5 ha is 2.00 tons per hectare', () {
      final scaled = YieldCalc.tonsPerHectareScaled2(harvest: harvest, area: field);
      expect(scaled, 200);
      expect(YieldCalc.formatTonsPerHectare(scaled), '2.00');
    });

    test('a total crop failure yields zero, not an error', () {
      // spec edge case "Total crop failure".
      final scaled =
          YieldCalc.tonsPerHectareScaled2(harvest: Grams.zero, area: field);
      expect(scaled, 0);
    });
  });

  group('MoneyCalc (FR-029, FR-030, FR-035, FR-040, FR-041)', () {
    test('totals a season of expenses', () {
      final total = MoneyCalc.totalExpenses([
        Centavos.fromPesos(3500),
        Centavos.fromPesos(12000),
        Centavos.fromPesos(8000),
      ]);
      expect(total.format(), '23,500.00');
    });

    test('breaks expenses down by category with shares', () {
      final breakdown = MoneyCalc.categoryBreakdown({
        ExpenseCategory.labor: Centavos.fromPesos(3500),
        ExpenseCategory.landPreparation: Centavos.fromPesos(12000),
        ExpenseCategory.seeds: Centavos.fromPesos(8000),
        ExpenseCategory.hauling: Centavos.zero,
      });
      // Ordered by amount descending; zero-value categories omitted.
      expect(breakdown.map((s) => s.category).toList(), [
        ExpenseCategory.landPreparation,
        ExpenseCategory.seeds,
        ExpenseCategory.labor,
      ]);
      expect(breakdown.first.formatPercent(), '51.1%'); // 12000/23500
      expect(breakdown.last.formatPercent(), '14.9%'); // 3500/23500
    });

    test('a sale of 4,000 kg at PHP 20.00/kg is PHP 80,000', () {
      final revenue = MoneyCalc.saleRevenue(
        quantity: Grams.fromKg(4000),
        pricePerKg: Centavos.parse('20.00'),
      );
      expect(revenue.format(), '80,000.00');
    });

    test('net profit is revenue minus expenses', () {
      final profit = MoneyCalc.netProfit(
        revenue: Centavos.fromPesos(80000),
        expenses: expenses,
      );
      expect(profit.format(), '56,500.00');
    });

    test('a loss is reported as a negative amount', () {
      final profit = MoneyCalc.netProfit(
        revenue: Centavos.fromPesos(10000),
        expenses: expenses,
      );
      expect(profit.isNegative, isTrue);
      expect(profit.format(), '-13,500.00');
    });

    test('cost per kg produced is PHP 4.70', () {
      // 23,500 pesos over 5,000 kg harvested, on the fresh-weight basis.
      final cost = MoneyCalc.costPerKg(totalExpenses: expenses, harvested: harvest);
      expect(cost!.format(), '4.70');
    });

    test('cost per kg is not applicable when nothing was harvested', () {
      // FR-041: never a division error.
      expect(
        MoneyCalc.costPerKg(totalExpenses: expenses, harvested: Grams.zero),
        isNull,
      );
    });

    test('post-harvest costs move the provisional profit (quickstart Scenario 2)', () {
      final withHauling = MoneyCalc.totalExpenses([
        expenses,
        Centavos.fromPesos(4000),
      ]);
      expect(withHauling.format(), '27,500.00');
      expect(
        MoneyCalc.netProfit(revenue: Centavos.fromPesos(80000), expenses: withHauling)
            .format(),
        '52,500.00',
      );
    });
  });

  group('End-to-end: quickstart Scenario 1 figures', () {
    test('every reported figure matches the hand calculation', () {
      final revenue = MoneyCalc.saleRevenue(
        quantity: Grams.fromKg(4000),
        pricePerKg: Centavos.parse('20.00'),
      );
      final remaining = harvest - Grams.fromKg(4000);

      expect(expenses.format(), '23,500.00');
      expect(revenue.format(), '80,000.00');
      expect(
        MoneyCalc.netProfit(revenue: revenue, expenses: expenses).format(),
        '56,500.00',
      );
      expect(harvest.formatTons(), '5.00');
      expect(
        YieldCalc.formatTonsPerHectare(
          YieldCalc.tonsPerHectareScaled2(harvest: harvest, area: field),
        ),
        '2.00',
      );
      expect(
        MoneyCalc.costPerKg(totalExpenses: expenses, harvested: harvest)!.format(),
        '4.70',
      );
      expect(remaining.formatKg(), '1,000.0');
    });
  });
}
