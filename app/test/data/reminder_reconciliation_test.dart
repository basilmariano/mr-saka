import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:saka/data/local/database.dart';
import 'package:saka/data/local/repositories/application_repository.dart';
import 'package:saka/data/local/repositories/cropping_repository.dart';
import 'package:saka/data/local/repositories/expense_repository.dart';
import 'package:saka/data/local/repositories/field_repository.dart';
import 'package:saka/data/local/tables.dart';
import 'package:saka/data/reference/template_lookup.dart';
import 'package:saka/data/sync/reminder_reconciliation.dart';
import 'package:saka/domain/model/calendar_date.dart';
import 'package:saka/domain/model/centavos.dart';
import 'package:saka/domain/model/enums.dart';
import 'package:saka/domain/model/grams.dart';
import 'package:saka/domain/model/square_metres.dart';
import 'package:saka/platform/reminders/reminder_scheduler.dart';

/// FR-019, FR-019a, FR-019b end to end through the database.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SakaDatabase db;
  late FieldRepository fields;
  late CroppingRepository croppings;
  late ApplicationRepository applications;
  late FakeReminderScheduler scheduler;
  late ReminderReconciliation reconciliation;

  const today = CalendarDate(2026, 3, 1);
  const templateId = '00000000-0000-4000-8000-000000000301';

  setUp(() async {
    db = SakaDatabase.memory();
    fields = FieldRepository(db);
    final expenses = ExpenseRepository(db);
    applications = ApplicationRepository(db, expenses: expenses);
    croppings = CroppingRepository(
      db,
      applications: applications,
      templates: TemplateLookup(db),
    );
    scheduler = FakeReminderScheduler();
    reconciliation = ReminderReconciliation(
      database: db,
      scheduler: scheduler,
      croppings: croppings,
      applications: applications,
      fields: fields,
    );

    await db.into(db.varieties).insert(
          VarietiesCompanion.insert(
            id: 'v1',
            name: 'NSIC Rc222',
            crop: CropDb.rice,
            maturityDays: const Value(110),
            source: SourceDb.seed,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
    // A template with REAL rates, so bag scaling is actually exercised — the
    // shipped seed bundle is still all zeros (research.md R9).
    await db.into(db.fertilizerTemplates).insert(
          FertilizerTemplatesCompanion.insert(
            id: templateId,
            crop: CropDb.rice,
            plantingMethod: PlantingMethodDb.transplanted,
            source: SourceDb.seed,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
    for (final (i, days, product, kg) in [
      (0, 0, 'Complete 14-14-14', 100),
      (1, 14, 'Urea 46-0-0', 100),
      (2, 35, 'Urea 46-0-0', 50),
    ]) {
      await db.into(db.fertilizerTemplateSteps).insert(
            FertilizerTemplateStepsCompanion.insert(
              id: 'step-$i',
              templateId: templateId,
              daysAfterPlanting: days,
              growthStage: 'Stage $i',
              product: product,
              ratePerHectareGrams: Grams.fromKg(kg).value,
              sortOrder: i,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
    }
  });
  tearDown(() => db.close());

  Future<String> startCropping() async {
    final field = await fields.create(
      name: 'Field 1',
      area: SquareMetres.parseHectares('2.5'),
    );
    final cropping = await croppings.start(
      fieldId: field.id,
      crop: Crop.rice,
      varietyId: 'v1',
      varietyMaturityDays: 110,
      plantingMethod: PlantingMethod.transplanted,
      growingSeason: GrowingSeason.wet,
      plantingDate: today,
      today: today,
    );
    return cropping.id;
  }

  group('FR-014 — schedule generation at cropping start', () {
    test('a new cropping gets the template\'s steps, snapshotted', () async {
      final croppingId = await startCropping();
      final schedule = await applications.forCropping(croppingId);

      expect(schedule, hasLength(3));
      expect(schedule.map((a) => a.growthStage).toList(),
          ['Stage 0', 'Stage 1', 'Stage 2']);
      expect(schedule[1].recommendedProduct, 'Urea 46-0-0');
      expect(schedule[1].daysAfterPlanting, 14);
    });

    test('scales the recommendation to the field (SC-004)', () async {
      final croppingId = await startCropping();
      final schedule = await applications.forCropping(croppingId);
      final area = SquareMetres.parseHectares('2.5');

      // 100 kg/ha on 2.5 ha is 250 kg, which is 5.0 bags of 50 kg.
      expect(schedule[1].recommendedQuantity(area).formatKg(), '250.0');
      expect(schedule[1].recommendedQuantity(area).formatBags(), '5.0');
    });

    test('derives each due date from the planting date (FR-017)', () async {
      final croppingId = await startCropping();
      final schedule = await applications.forCropping(croppingId);

      expect(schedule[1].dueDate(today), const CalendarDate(2026, 3, 15));
      expect(schedule[2].dueDate(today), const CalendarDate(2026, 4, 5));
    });

    test('editing the template does not touch a running schedule (FR-025)',
        () async {
      final croppingId = await startCropping();
      await (db.update(db.fertilizerTemplateSteps)
            ..where((s) => s.id.equals('step-1')))
          .write(
        FertilizerTemplateStepsCompanion(
          ratePerHectareGrams: Value(Grams.fromKg(999).value),
        ),
      );

      final schedule = await applications.forCropping(croppingId);
      expect(schedule[1].ratePerHectare.formatKg(), '100.0');
    });
  });

  group('FR-021 — the linked expense', () {
    test('a recorded cost creates exactly one fertilizer expense', () async {
      final croppingId = await startCropping();
      final schedule = await applications.forCropping(croppingId);
      final expenses = ExpenseRepository(db);

      await applications.markDone(
        applicationId: schedule[1].id,
        actualDate: const CalendarDate(2026, 3, 15),
        actualProduct: 'Urea 46-0-0',
        actualQuantity: Grams.fromKg(250),
        cost: Centavos.fromPesos(7500),
      );

      final logged = await expenses.forCropping(croppingId);
      expect(logged, hasLength(1));
      expect(logged.single.category, ExpenseCategory.fertilizer);
      expect(logged.single.amount.format(), '7,500.00');
    });

    test('editing the cost moves the total by the difference, not the whole',
        () async {
      // SC-006. A second expense here would silently overstate the season.
      final croppingId = await startCropping();
      final schedule = await applications.forCropping(croppingId);
      final expenses = ExpenseRepository(db);

      await applications.markDone(
        applicationId: schedule[1].id,
        actualDate: const CalendarDate(2026, 3, 15),
        actualProduct: 'Urea 46-0-0',
        actualQuantity: Grams.fromKg(250),
        cost: Centavos.fromPesos(7500),
      );
      await applications.markDone(
        applicationId: schedule[1].id,
        actualDate: const CalendarDate(2026, 3, 15),
        actualProduct: 'Urea 46-0-0',
        actualQuantity: Grams.fromKg(250),
        cost: Centavos.fromPesos(8000),
      );

      expect(await expenses.forCropping(croppingId), hasLength(1));
      expect((await expenses.total(croppingId)).format(), '8,000.00');
    });

    test('skipping an application removes any expense it created (FR-022)',
        () async {
      final croppingId = await startCropping();
      final schedule = await applications.forCropping(croppingId);
      final expenses = ExpenseRepository(db);

      await applications.markDone(
        applicationId: schedule[1].id,
        actualDate: today,
        actualProduct: 'Urea',
        actualQuantity: Grams.fromKg(250),
        cost: Centavos.fromPesos(7500),
      );
      await applications.markSkipped(applicationId: schedule[1].id, reason: 'Rain');

      expect(await expenses.forCropping(croppingId), isEmpty);
      expect((await applications.byId(schedule[1].id))!.skipReason, 'Rain');
    });

    test('deleting an application takes its expense with it', () async {
      final croppingId = await startCropping();
      final schedule = await applications.forCropping(croppingId);
      final expenses = ExpenseRepository(db);

      await applications.markDone(
        applicationId: schedule[1].id,
        actualDate: today,
        actualProduct: 'Urea',
        actualQuantity: Grams.fromKg(250),
        cost: Centavos.fromPesos(7500),
      );
      await applications.delete(schedule[1].id);

      expect(await expenses.forCropping(croppingId), isEmpty);
    });
  });

  group('FR-011a — first application done advances the cropping', () {
    test('marking one done moves planted to growing immediately', () async {
      final croppingId = await startCropping();
      final schedule = await applications.forCropping(croppingId);
      expect((await croppings.byId(croppingId))!.status, CroppingStatus.planted);

      await applications.markDone(
        applicationId: schedule.first.id,
        actualDate: today,
        actualProduct: 'Complete 14-14-14',
        actualQuantity: Grams.fromKg(250),
      );
      await croppings.refreshStatuses(today);

      expect((await croppings.byId(croppingId))!.status, CroppingStatus.growing);
    });
  });

  group('FR-019 — reconciliation', () {
    test('schedules two reminders per pending application', () async {
      await startCropping();
      final count = await reconciliation.reconcile(
        today: today,
        remindersEnabled: true,
      );

      // 3 steps x 2 reminders; the day-0 step's lead date is already past.
      expect(count, scheduler.scheduled.length);
      expect(scheduler.scheduled, isNotEmpty);
      expect(
        scheduler.scheduled.first.quantityBags,
        isNotEmpty,
        reason: 'the notification must carry the bags to buy (SC-004)',
      );
    });

    test('is idempotent — running twice does not stack reminders', () async {
      await startCropping();
      await reconciliation.reconcile(today: today, remindersEnabled: true);
      final first = scheduler.scheduled.length;
      await reconciliation.reconcile(today: today, remindersEnabled: true);

      expect(scheduler.scheduled, hasLength(first));
      expect(scheduler.replaceAllCalls, 2);
    });

    test('FR-019a — switched off cancels everything', () async {
      await startCropping();
      await reconciliation.reconcile(today: today, remindersEnabled: true);
      expect(scheduler.scheduled, isNotEmpty);

      final count = await reconciliation.reconcile(
        today: today,
        remindersEnabled: false,
      );

      expect(count, 0);
      expect(scheduler.scheduled, isEmpty);
    });

    test('the setting persists and defaults to on', () async {
      expect(await reconciliation.remindersEnabled(), isTrue);
      await reconciliation.setRemindersEnabled(false);
      expect(await reconciliation.remindersEnabled(), isFalse);
    });

    test('FR-019b — a harvested cropping schedules nothing', () async {
      final croppingId = await startCropping();
      await croppings.markHarvested(croppingId);

      final count = await reconciliation.reconcile(
        today: today,
        remindersEnabled: true,
      );
      expect(count, 0);
    });
  });
}
