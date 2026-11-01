import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:saka/data/local/database.dart';
import 'package:saka/data/local/repositories/cropping_repository.dart';
import 'package:saka/data/local/repositories/expense_repository.dart';
import 'package:saka/data/local/repositories/harvest_repository.dart';
import 'package:saka/data/local/repositories/result_repository.dart';
import 'package:saka/data/local/repositories/sale_repository.dart';
import 'package:saka/data/local/repositories/field_repository.dart';
import 'package:saka/data/local/tables.dart';
import 'package:saka/data/local/write_through.dart';
import 'package:saka/domain/calc/yield_calc.dart';
import 'package:saka/domain/model/calendar_date.dart';
import 'package:saka/domain/model/centavos.dart';
import 'package:saka/domain/model/enums.dart';
import 'package:saka/domain/model/grams.dart';
import 'package:saka/domain/model/square_metres.dart';
import 'package:saka/domain/rules/weight_basis.dart';

/// User Story 1 end to end, through the real database.
///
/// These are the quickstart.md scenarios expressed at the repository level, so they
/// run headlessly in CI. The on-device integration_test files cover the same ground
/// through the UI.
void main() {
  late SakaDatabase db;
  late FieldRepository fields;
  late CroppingRepository croppings;
  late ExpenseRepository expenses;
  late HarvestRepository harvests;
  late SaleRepository sales;
  late ResultRepository results;

  const today = CalendarDate(2026, 3, 1);
  const varietyId = 'variety-1';

  setUp(() async {
    db = SakaDatabase.memory();
    fields = FieldRepository(db);
    croppings = CroppingRepository(db);
    expenses = ExpenseRepository(db);
    harvests = HarvestRepository(db);
    sales = SaleRepository(db);
    results = ResultRepository(expenses: expenses, harvests: harvests, sales: sales);

    await db.into(db.varieties).insert(
          VarietiesCompanion.insert(
            id: varietyId,
            name: 'NSIC Rc222',
            crop: CropDb.rice,
            maturityDays: const Value(110),
            source: SourceDb.seed,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  });
  tearDown(() => db.close());

  Future<(String fieldId, String croppingId)> startCropping({
    CalendarDate plantingDate = today,
    String areaHa = '2.5',
  }) async {
    final field = await fields.create(
      name: 'Field 1',
      area: SquareMetres.parseHectares(areaHa),
    );
    final cropping = await croppings.start(
      fieldId: field.id,
      crop: Crop.rice,
      varietyId: varietyId,
      varietyMaturityDays: 110,
      plantingMethod: PlantingMethod.transplanted,
      growingSeason: GrowingSeason.wet,
      plantingDate: plantingDate,
      today: today,
    );
    return (field.id, cropping.id);
  }

  group('Scenario 1 — the bottom line', () {
    test('every reported figure matches the hand calculation', () async {
      final (fieldId, croppingId) = await startCropping();

      for (final (category, pesos) in [
        (ExpenseCategory.labor, 3500),
        (ExpenseCategory.landPreparation, 12000),
        (ExpenseCategory.seeds, 8000),
      ]) {
        await expenses.create(
          croppingId: croppingId,
          date: today,
          category: category,
          amount: Centavos.fromPesos(pesos),
        );
      }

      // 100 sacks x 50 kg average WET per sack.
      await harvests.record(
        croppingId: croppingId,
        date: const CalendarDate(2026, 6, 19),
        sacks: 100,
        avgWetPerSack: Grams.fromKg(50),
      );
      await croppings.markHarvested(croppingId);

      var cropping = (await croppings.byId(croppingId))!;
      await sales.record(
        cropping: cropping,
        quantity: Grams.fromKg(4000),
        pricePerKg: Centavos.parse('20.00'),
        buyer: 'Local trader',
        date: const CalendarDate(2026, 6, 25),
      );

      cropping = (await croppings.byId(croppingId))!;
      final field = (await fields.byId(fieldId))!;
      final result =
          await results.forCropping(cropping: cropping, area: field.area);

      expect(result.totalExpenses.format(), '23,500.00');
      expect(result.revenue.format(), '80,000.00');
      expect(result.netProfit.format(), '56,500.00');
      expect(result.harvested!.formatTons(), '5.00');
      expect(
        YieldCalc.formatTonsPerHectare(result.tonsPerHectareScaled2),
        '2.00',
      );
      expect(result.costPerKg!.format(), '4.70');
      expect(result.remaining!.quantity.formatKg(), '1,000.0');
      expect(result.state, ResultState.provisional);
    });

    test('expense breakdown shares add up', () async {
      final (_, croppingId) = await startCropping();
      await expenses.create(
        croppingId: croppingId,
        date: today,
        category: ExpenseCategory.labor,
        amount: Centavos.fromPesos(3500),
      );
      await expenses.create(
        croppingId: croppingId,
        date: today,
        category: ExpenseCategory.seeds,
        amount: Centavos.fromPesos(6500),
      );

      final breakdown = await expenses.breakdown(croppingId);
      expect(breakdown.first.category, ExpenseCategory.seeds);
      expect(breakdown.first.formatPercent(), '65.0%');
      expect(breakdown.last.formatPercent(), '35.0%');
    });

    test('before harvest the result is in progress, not a loss', () async {
      final (fieldId, croppingId) = await startCropping();
      await expenses.create(
        croppingId: croppingId,
        date: today,
        category: ExpenseCategory.landPreparation,
        amount: Centavos.fromPesos(12000),
      );

      final cropping = (await croppings.byId(croppingId))!;
      final field = (await fields.byId(fieldId))!;
      final result =
          await results.forCropping(cropping: cropping, area: field.area);

      expect(result.state, ResultState.inProgress);
      expect(result.showsProfit, isFalse);
      expect(result.totalExpenses.format(), '12,000.00');
    });

    test('a total crop failure reports cost per kg as not applicable', () async {
      final (fieldId, croppingId) = await startCropping();
      await expenses.create(
        croppingId: croppingId,
        date: today,
        category: ExpenseCategory.seeds,
        amount: Centavos.fromPesos(8000),
      );
      await harvests.record(
        croppingId: croppingId,
        date: today,
        totalWet: Grams.zero,
      );
      await croppings.markHarvested(croppingId);

      final cropping = (await croppings.byId(croppingId))!;
      final field = (await fields.byId(fieldId))!;
      final result =
          await results.forCropping(cropping: cropping, area: field.area);

      expect(result.costPerKg, isNull);
      expect(result.tonsScaled2, 0);
      expect(result.netProfit.isNegative, isTrue);
    });
  });

  group('Scenario 2 — post-harvest costs and closing', () {
    test('hauling logged after harvest moves the provisional profit', () async {
      final (fieldId, croppingId) = await startCropping();
      await expenses.create(
        croppingId: croppingId,
        date: today,
        category: ExpenseCategory.landPreparation,
        amount: Centavos.fromPesos(23500),
      );
      await harvests.record(
        croppingId: croppingId,
        date: const CalendarDate(2026, 6, 19),
        totalWet: Grams.fromKg(5000),
      );
      await croppings.markHarvested(croppingId);

      var cropping = (await croppings.byId(croppingId))!;
      await sales.record(
        cropping: cropping,
        quantity: Grams.fromKg(4000),
        pricePerKg: Centavos.parse('20.00'),
        buyer: 'Trader',
        date: const CalendarDate(2026, 6, 25),
      );

      // FR-031a: a cost dated 5 days AFTER the harvest is accepted without warning.
      await expenses.create(
        croppingId: croppingId,
        date: const CalendarDate(2026, 6, 24),
        category: ExpenseCategory.hauling,
        amount: Centavos.fromPesos(4000),
      );

      cropping = (await croppings.byId(croppingId))!;
      final field = (await fields.byId(fieldId))!;
      final result =
          await results.forCropping(cropping: cropping, area: field.area);

      expect(result.totalExpenses.format(), '27,500.00');
      expect(result.netProfit.format(), '52,500.00');
      expect(result.state, ResultState.provisional);
    });

    test('closing makes the result final and rejects further records', () async {
      final (fieldId, croppingId) = await startCropping();
      await harvests.record(
        croppingId: croppingId,
        date: today,
        totalWet: Grams.fromKg(5000),
      );
      await croppings.markHarvested(croppingId);
      await croppings.close(croppingId);

      final cropping = (await croppings.byId(croppingId))!;
      final field = (await fields.byId(fieldId))!;
      final result =
          await results.forCropping(cropping: cropping, area: field.area);

      expect(cropping.status, CroppingStatus.closed);
      expect(result.state, ResultState.isFinal);
      expect(cropping.status.acceptsRecords, isFalse);
    });

    test('a growing cropping cannot be closed — closing follows harvest', () async {
      final (_, croppingId) = await startCropping();
      await croppings.close(croppingId);
      expect((await croppings.byId(croppingId))!.status, CroppingStatus.planted);
    });

    test('reopening a closed cropping restores editing', () async {
      final (_, croppingId) = await startCropping();
      await harvests.record(croppingId: croppingId, date: today, totalWet: Grams.fromKg(1));
      await croppings.markHarvested(croppingId);
      await croppings.close(croppingId);
      await croppings.reopen(croppingId);
      expect((await croppings.byId(croppingId))!.status, CroppingStatus.harvested);
    });
  });

  group('Scenario 3 — two open croppings on one field', () {
    test('refuses a new cropping while one is in the ground', () async {
      final (fieldId, croppingId) = await startCropping();
      expect(
        () => croppings.start(
          fieldId: fieldId,
          crop: Crop.rice,
          varietyId: varietyId,
          varietyMaturityDays: 110,
          plantingMethod: PlantingMethod.transplanted,
          growingSeason: GrowingSeason.dry,
          plantingDate: today,
          today: today,
        ),
        throwsA(
          isA<FieldBusy>().having((e) => e.occupyingCroppingId, 'names it', croppingId),
        ),
      );
    });

    test('allows replanting once harvested, and asks which cropping owns a cost',
        () async {
      final (fieldId, firstId) = await startCropping();
      await harvests.record(croppingId: firstId, date: today, totalWet: Grams.fromKg(5000));
      await croppings.markHarvested(firstId);

      // FR-008a: replanting is never blocked by outstanding sales records.
      final second = await croppings.start(
        fieldId: fieldId,
        crop: Crop.corn,
        varietyId: varietyId,
        varietyMaturityDays: null,
        plantingMethod: PlantingMethod.directSeeded,
        growingSeason: GrowingSeason.dry,
        plantingDate: const CalendarDate(2026, 7, 1),
        today: const CalendarDate(2026, 7, 1),
      );

      // FR-008b: the farmer is prompted, not forced, to close the previous one.
      expect(await croppings.harvestedAwaitingClosure(fieldId), isNotNull);

      // FR-031b: the field now has two open croppings, so an expense must be
      // attributed deliberately — the sharpest correctness risk in the feature.
      final open = await croppings.openForField(fieldId);
      expect(open.map((c) => c.id).toSet(), {firstId, second.id});

      await expenses.create(
        croppingId: firstId,
        date: const CalendarDate(2026, 7, 5),
        category: ExpenseCategory.hauling,
        amount: Centavos.fromPesos(4000),
      );
      expect((await expenses.total(firstId)).format(), '4,000.00');
      expect((await expenses.total(second.id)).format(), '0.00');
    });
  });

  group('Scenario 9 — wet and dry weight', () {
    test('remaining counts down from the dried weight, not the harvest', () async {
      final (_, croppingId) = await startCropping();
      await harvests.record(
        croppingId: croppingId,
        date: today,
        totalWet: Grams.fromKg(5000),
      );
      await croppings.markHarvested(croppingId);
      await croppings.setWeightBasis(croppingId, WeightBasis.dry);
      await croppings.setDriedWeight(croppingId, Grams.fromKg(4200));

      final cropping = (await croppings.byId(croppingId))!;
      await sales.record(
        cropping: cropping,
        quantity: Grams.fromKg(4000),
        pricePerKg: Centavos.parse('23.00'),
        buyer: 'Trader',
        date: today,
      );

      final remaining = await sales.remaining((await croppings.byId(croppingId))!);
      expect(remaining!.quantity.formatKg(), '200.0'); // not 1,000
      expect(remaining.basis, WeightBasis.dry);
    });

    test('a dry sale is refused before the dried weight is recorded', () async {
      final (_, croppingId) = await startCropping();
      await harvests.record(croppingId: croppingId, date: today, totalWet: Grams.fromKg(5000));
      await croppings.markHarvested(croppingId);
      await croppings.setWeightBasis(croppingId, WeightBasis.dry);

      final cropping = (await croppings.byId(croppingId))!;
      expect(
        () => sales.record(
          cropping: cropping,
          quantity: Grams.fromKg(100),
          pricePerKg: Centavos.parse('23.00'),
          buyer: 'Trader',
          date: today,
        ),
        throwsA(isA<SaleRejected>()
            .having((e) => e.reason, 'reason', SaleRejection.driedWeightMissing)),
      );
    });

    test('rejects a sale exceeding the remaining quantity', () async {
      final (_, croppingId) = await startCropping();
      await harvests.record(croppingId: croppingId, date: today, totalWet: Grams.fromKg(5000));
      await croppings.markHarvested(croppingId);

      final cropping = (await croppings.byId(croppingId))!;
      expect(
        () => sales.record(
          cropping: cropping,
          quantity: Grams.fromKg(5001),
          pricePerKg: Centavos.parse('20.00'),
          buyer: 'Trader',
          date: today,
        ),
        throwsA(isA<SaleRejected>()
            .having((e) => e.reason, 'reason', SaleRejection.exceedsRemaining)),
      );
    });

    test('rejects a sale with no harvest recorded', () async {
      final (_, croppingId) = await startCropping();
      final cropping = (await croppings.byId(croppingId))!;
      expect(
        () => sales.record(
          cropping: cropping,
          quantity: Grams.fromKg(10),
          pricePerKg: Centavos.parse('20.00'),
          buyer: 'Trader',
          date: today,
        ),
        throwsA(isA<SaleRejected>()
            .having((e) => e.reason, 'reason', SaleRejection.noHarvest)),
      );
    });
  });

  group('Scenario 10 — status transitions', () {
    test('a cropping planted today starts planted', () async {
      final (_, croppingId) = await startCropping();
      expect((await croppings.byId(croppingId))!.status, CroppingStatus.planted);
    });

    test('advances to growing on day 10 with no application done', () async {
      final (_, croppingId) = await startCropping();
      final changed = await croppings.refreshStatuses(const CalendarDate(2026, 3, 11));
      expect(changed, 1);
      expect((await croppings.byId(croppingId))!.status, CroppingStatus.growing);
    });

    test('does not advance before day 10', () async {
      final (_, croppingId) = await startCropping();
      await croppings.refreshStatuses(const CalendarDate(2026, 3, 9));
      expect((await croppings.byId(croppingId))!.status, CroppingStatus.planted);
    });

    test('a cropping backdated 15 days starts in growing', () async {
      final field = await fields.create(
        name: 'Field 2',
        area: SquareMetres.parseHectares('1'),
      );
      final cropping = await croppings.start(
        fieldId: field.id,
        crop: Crop.rice,
        varietyId: varietyId,
        varietyMaturityDays: 110,
        plantingMethod: PlantingMethod.directSeeded,
        growingSeason: GrowingSeason.dry,
        plantingDate: const CalendarDate(2026, 2, 14),
        today: const CalendarDate(2026, 3, 1),
      );
      expect(cropping.status, CroppingStatus.growing);
    });
  });

  group('Fields', () {
    test('a field with croppings cannot be deleted, only archived', () async {
      final (fieldId, _) = await startCropping();
      expect(await fields.deleteIfUnused(fieldId), isFalse);

      await fields.archive(fieldId);
      expect((await fields.byId(fieldId))!.archived, isTrue);
      expect(await fields.listActive(), isEmpty);
    });

    test('an unused field can be deleted', () async {
      final field = await fields.create(
        name: 'Unused',
        area: SquareMetres.parseHectares('1'),
      );
      expect(await fields.deleteIfUnused(field.id), isTrue);
      expect(await fields.listActive(), isEmpty);
    });
  });

  test('every write through the repositories queued for sync', () async {
    // sync-protocol.md I1: nothing reaches the database without an outbox entry.
    final (_, croppingId) = await startCropping();
    await expenses.create(
      croppingId: croppingId,
      date: today,
      category: ExpenseCategory.labor,
      amount: Centavos.fromPesos(100),
    );
    final queued = await db.pendingOutbox();
    expect(
      queued.map((e) => e.entityType).toList(),
      ['field', 'cropping', 'expense'],
    );
  });
}
