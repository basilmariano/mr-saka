import 'package:saka/domain/model/calendar_date.dart';
import 'package:saka/domain/model/centavos.dart';
import 'package:saka/domain/model/enums.dart';
import 'package:saka/domain/model/grams.dart';
import 'package:saka/domain/model/square_metres.dart';
import 'package:saka/domain/rules/cropping_status.dart';
import 'package:saka/domain/rules/field_occupancy.dart';
import 'package:saka/domain/rules/validation.dart';
import 'package:saka/domain/rules/weight_basis.dart';
import 'package:test/test.dart';

void main() {
  const planting = CalendarDate(2026, 3, 1);

  group('Cropping status (FR-011a to FR-011c, FR-012b)', () {
    test('stays planted before day 10 with no application done', () {
      expect(
        CroppingStatusRules.derive(
          current: CroppingStatus.planted,
          plantingDate: planting,
          today: const CalendarDate(2026, 3, 9),
          anyApplicationDone: false,
        ),
        CroppingStatus.planted,
      );
    });

    test('advances to growing on day 10 with no application done', () {
      expect(
        CroppingStatusRules.derive(
          current: CroppingStatus.planted,
          plantingDate: planting,
          today: const CalendarDate(2026, 3, 11),
          anyApplicationDone: false,
        ),
        CroppingStatus.growing,
      );
    });

    test('advances immediately when the first application is marked done', () {
      // quickstart Scenario 10 step 2: done on day 3, growing on day 3.
      expect(
        CroppingStatusRules.derive(
          current: CroppingStatus.planted,
          plantingDate: planting,
          today: const CalendarDate(2026, 3, 4),
          anyApplicationDone: true,
        ),
        CroppingStatus.growing,
      );
    });

    test('a cropping backdated more than 10 days starts in growing', () {
      // FR-011c.
      expect(
        CroppingStatusRules.initialStatus(
          plantingDate: planting,
          today: const CalendarDate(2026, 3, 16),
        ),
        CroppingStatus.growing,
      );
    });

    test('never advances harvested or closed backwards or forwards', () {
      for (final status in [CroppingStatus.harvested, CroppingStatus.closed]) {
        expect(
          CroppingStatusRules.derive(
            current: status,
            plantingDate: planting,
            today: const CalendarDate(2027, 1, 1),
            anyApplicationDone: true,
          ),
          status,
        );
      }
    });

    test('a closed cropping rejects records until reopened', () {
      expect(CroppingStatusRules.acceptsRecords(CroppingStatus.closed), isFalse);
      expect(CroppingStatusRules.acceptsRecords(CroppingStatus.harvested), isTrue);
      expect(CroppingStatusRules.canReopen(CroppingStatus.closed), isTrue);
    });

    test('only a harvested cropping can be closed, and only deliberately', () {
      expect(CroppingStatusRules.canClose(CroppingStatus.harvested), isTrue);
      expect(CroppingStatusRules.canClose(CroppingStatus.growing), isFalse);
    });
  });

  group('Field occupancy (FR-008, FR-008a, FR-008b, FR-031b)', () {
    test('refuses a new cropping while one is in the ground', () {
      expect(
        FieldOccupancyRules.canStartNewCropping([CroppingStatus.growing]),
        isFalse,
      );
      expect(
        FieldOccupancyRules.canStartNewCropping([CroppingStatus.planted]),
        isFalse,
      );
    });

    test('allows replanting once the previous cropping is harvested', () {
      // FR-008a: recording sales never blocks the next planting.
      expect(
        FieldOccupancyRules.canStartNewCropping([CroppingStatus.harvested]),
        isTrue,
      );
      expect(
        FieldOccupancyRules.canStartNewCropping([CroppingStatus.closed]),
        isTrue,
      );
    });

    test('prompts to close the previous cropping, without forcing it', () {
      expect(
        FieldOccupancyRules.shouldPromptToClosePrevious([CroppingStatus.harvested]),
        isTrue,
      );
    });

    test('requires the farmer to pick when a field has two open croppings', () {
      // FR-031b: the app "MUST NOT silently default to either".
      expect(
        FieldOccupancyRules.requiresCroppingChoice(
          [CroppingStatus.harvested, CroppingStatus.planted],
        ),
        isTrue,
      );
      expect(
        FieldOccupancyRules.requiresCroppingChoice([CroppingStatus.growing]),
        isFalse,
      );
      expect(
        FieldOccupancyRules.requiresCroppingChoice(
          [CroppingStatus.closed, CroppingStatus.growing],
        ),
        isFalse,
      );
    });
  });

  group('Weight basis (FR-034c, FR-036, FR-037, FR-037a)', () {
    final freshHarvest = Grams.fromKg(5000);

    test('sold wet: remaining counts down from the fresh harvest', () {
      final sellable = WeightBasisRules.sellableQuantity(
        freshHarvest: freshHarvest,
        basis: WeightBasis.wet,
        driedWeight: null,
      );
      final remaining = WeightBasisRules.remainingQuantity(
        sellable: sellable,
        soldQuantities: [Grams.fromKg(4000)],
      );
      expect(remaining!.quantity.formatKg(), '1,000.0');
      expect(remaining.basis, WeightBasis.wet);
    });

    test('sold dry: remaining counts down from the dried weight, not the harvest', () {
      // quickstart Scenario 9: harvest 5,000 kg wet, dried to 4,200 kg, sell 4,000 kg
      // dry. Remaining is 200 kg dry - NOT the 1,000 kg a naive subtraction gives.
      final sellable = WeightBasisRules.sellableQuantity(
        freshHarvest: freshHarvest,
        basis: WeightBasis.dry,
        driedWeight: Grams.fromKg(4200),
      );
      final remaining = WeightBasisRules.remainingQuantity(
        sellable: sellable,
        soldQuantities: [Grams.fromKg(4000)],
      );
      expect(remaining!.quantity.formatKg(), '200.0');
      expect(remaining.basis, WeightBasis.dry);
    });

    test('sold dry with no dried weight recorded yet is unknown, not guessed', () {
      expect(
        WeightBasisRules.sellableQuantity(
          freshHarvest: freshHarvest,
          basis: WeightBasis.dry,
          driedWeight: null,
        ),
        isNull,
      );
    });

    test('refuses to subtract dry from wet', () {
      // FR-037a, enforced as an exception so the mistake cannot reach a farmer.
      final wet = Lot(Grams.fromKg(5000), WeightBasis.wet);
      final dry = Lot(Grams.fromKg(4000), WeightBasis.dry);
      expect(() => wet - dry, throwsA(isA<WeightBasisMismatch>()));
    });
  });

  group('Sale validation (FR-037)', () {
    final sellable = Lot(Grams.fromKg(5000), WeightBasis.wet);
    final remaining = Lot(Grams.fromKg(1000), WeightBasis.wet);

    test('accepts a sale within the remaining quantity', () {
      expect(
        SaleRules.validate(
          hasHarvest: true,
          sellable: sellable,
          remaining: remaining,
          quantity: Grams.fromKg(1000),
        ),
        isNull,
      );
    });

    test('rejects a sale with no harvest recorded', () {
      expect(
        SaleRules.validate(
          hasHarvest: false,
          sellable: null,
          remaining: null,
          quantity: Grams.fromKg(10),
        ),
        SaleRejection.noHarvest,
      );
    });

    test('rejects a sale exceeding the remaining quantity', () {
      expect(
        SaleRules.validate(
          hasHarvest: true,
          sellable: sellable,
          remaining: remaining,
          quantity: Grams.fromKg(1001),
        ),
        SaleRejection.exceedsRemaining,
      );
    });

    test('rejects a dry sale before the dried weight is recorded', () {
      expect(
        SaleRules.validate(
          hasHarvest: true,
          sellable: null,
          remaining: null,
          quantity: Grams.fromKg(100),
        ),
        SaleRejection.driedWeightMissing,
      );
    });
  });

  group('Validation (FR-002, FR-027, FR-031a)', () {
    test('rejects a zero or negative field area', () {
      expect(
        Validation.field(name: 'Field 1', area: SquareMetres.parseHectares('0')),
        contains(ValidationFailure.fieldAreaNotPositive),
      );
    });

    test('rejects a blank field name', () {
      expect(
        Validation.field(name: '  ', area: SquareMetres.parseHectares('2.5')),
        contains(ValidationFailure.fieldNameBlank),
      );
    });

    test('accepts a valid field', () {
      expect(
        Validation.field(name: 'Field 1', area: SquareMetres.parseHectares('2.5')),
        isEmpty,
      );
    });

    test('accepts an expense with no date constraint at all', () {
      // FR-031a and the "Expenses before planting" edge case: land prep precedes
      // planting and hauling follows harvest. Both are normal; neither warns.
      expect(Validation.expense(amount: Centavos.fromPesos(3500)), isEmpty);
    });

    test('rejects a zero expense amount', () {
      expect(
        Validation.expense(amount: Centavos.zero),
        contains(ValidationFailure.expenseAmountNotPositive),
      );
    });
  });
}
