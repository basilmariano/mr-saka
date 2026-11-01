import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:saka/data/local/database.dart';
import 'package:saka/data/local/repositories/application_repository.dart';
import 'package:saka/data/local/repositories/cropping_repository.dart';
import 'package:saka/data/local/repositories/expense_repository.dart';
import 'package:saka/data/local/repositories/field_repository.dart';
import 'package:saka/data/local/repositories/template_repository.dart';
import 'package:saka/data/local/tables.dart';
import 'package:saka/data/reference/reference_seeder.dart';
import 'package:saka/data/reference/template_lookup.dart';
import 'package:saka/domain/model/calendar_date.dart';
import 'package:saka/domain/model/enums.dart';
import 'package:saka/domain/model/grams.dart';
import 'package:saka/domain/model/reference.dart';
import 'package:saka/domain/model/square_metres.dart';

/// User Story 5 — FR-010, FR-024, FR-025, FR-026c.
///
/// quickstart.md Scenario 11 is the one that matters: a farmer's edit must
/// survive a published bundle update.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SakaDatabase db;
  late TemplateRepository templates;
  late TemplateLookup lookup;
  late CroppingRepository croppings;
  late ApplicationRepository applications;
  late FieldRepository fields;

  const today = CalendarDate(2026, 3, 1);
  const templateId = '00000000-0000-4000-8000-000000000301';

  setUp(() async {
    db = SakaDatabase.memory();
    templates = TemplateRepository(db);
    lookup = TemplateLookup(db);
    fields = FieldRepository(db);
    applications = ApplicationRepository(db, expenses: ExpenseRepository(db));
    croppings = CroppingRepository(
      db,
      applications: applications,
      templates: lookup,
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
    await db.into(db.fertilizerTemplates).insert(
          FertilizerTemplatesCompanion.insert(
            id: templateId,
            crop: CropDb.rice,
            plantingMethod: PlantingMethodDb.transplanted,
            source: SourceDb.seed,
            sourceAttribution: const Value('PhilRice test fixture'),
            bundleVersion: const Value(1),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
    await db.into(db.fertilizerTemplateSteps).insert(
          FertilizerTemplateStepsCompanion.insert(
            id: 'step-basal',
            templateId: templateId,
            daysAfterPlanting: 0,
            growthStage: 'Basal',
            product: 'Complete 14-14-14',
            ratePerHectareGrams: Grams.fromKg(100).value,
            sortOrder: 0,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
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

  group('FR-024 — editing a template', () {
    test('changing a rate is reflected in new croppings', () async {
      await templates.updateStep(
        templateId: templateId,
        stepId: 'step-basal',
        daysAfterPlanting: 0,
        growthStage: 'Basal',
        product: 'Complete 14-14-14',
        ratePerHectare: Grams.fromKg(120),
      );

      final croppingId = await startCropping();
      final schedule = await applications.forCropping(croppingId);
      expect(schedule.single.ratePerHectare.formatKg(), '120.0');
    });

    test('adding and removing steps', () async {
      await templates.addStep(
        templateId: templateId,
        daysAfterPlanting: 14,
        growthStage: 'Early tillering',
        product: 'Urea 46-0-0',
        ratePerHectare: Grams.fromKg(60),
      );
      var t = (await templates.byId(templateId))!;
      expect(t.steps, hasLength(2));
      expect(t.steps.last.growthStage, 'Early tillering');

      await templates.removeStep(templateId: templateId, stepId: 'step-basal');
      t = (await templates.byId(templateId))!;
      expect(t.steps, hasLength(1));
      expect(t.steps.single.growthStage, 'Early tillering');
    });

    test('reordering steps sticks', () async {
      await templates.addStep(
        templateId: templateId,
        daysAfterPlanting: 14,
        growthStage: 'Early tillering',
        product: 'Urea 46-0-0',
        ratePerHectare: Grams.fromKg(60),
      );
      var t = (await templates.byId(templateId))!;
      final ids = [for (final s in t.steps) s.id!];

      await templates.reorderSteps(
        templateId: templateId,
        stepIdsInOrder: ids.reversed.toList(),
      );
      t = (await templates.byId(templateId))!;
      expect(t.steps.first.growthStage, 'Early tillering');
      expect(t.steps.last.growthStage, 'Basal');
    });
  });

  group('FR-025 — a running cropping is not disturbed', () {
    test('editing after a cropping starts leaves its schedule alone', () async {
      // quickstart Scenario 11, step 3: the cropping started before the edit
      // keeps the steps it was given.
      final croppingId = await startCropping();
      expect(
        (await applications.forCropping(croppingId)).single
            .ratePerHectare
            .formatKg(),
        '100.0',
      );

      await templates.updateStep(
        templateId: templateId,
        stepId: 'step-basal',
        daysAfterPlanting: 0,
        growthStage: 'Basal',
        product: 'Complete 14-14-14',
        ratePerHectare: Grams.fromKg(120),
      );

      expect(
        (await applications.forCropping(croppingId)).single
            .ratePerHectare
            .formatKg(),
        '100.0',
        reason: 'a farmer mid-season must not have their schedule shift',
      );
    });

    test('removing a template step does not remove it from a running cropping',
        () async {
      final croppingId = await startCropping();
      await templates.removeStep(templateId: templateId, stepId: 'step-basal');
      expect(await applications.forCropping(croppingId), hasLength(1));
    });
  });

  group('FR-026c — the farmer\'s edit survives a published bundle', () {
    test('an edited template is claimed as the farmer\'s own', () async {
      expect((await templates.byId(templateId))!.source, ReferenceSource.seed);

      await templates.updateStep(
        templateId: templateId,
        stepId: 'step-basal',
        daysAfterPlanting: 0,
        growthStage: 'Basal',
        product: 'Complete 14-14-14',
        ratePerHectare: Grams.fromKg(120),
      );

      expect((await templates.byId(templateId))!.source, ReferenceSource.farmer);
    });

    test('a newer bundle does not overwrite it (quickstart Scenario 11)',
        () async {
      // The farmer follows their agriculturist: 100 -> 120 kg/ha.
      await templates.updateStep(
        templateId: templateId,
        stepId: 'step-basal',
        daysAfterPlanting: 0,
        growthStage: 'Basal',
        product: 'Complete 14-14-14',
        ratePerHectare: Grams.fromKg(120),
      );

      // A newer published bundle says 90.
      await ReferenceSeeder(db).apply(
        ReferenceBundle(
          version: 2,
          publishedAt: DateTime.utc(2026, 4, 1),
          isPlaceholder: false,
          varieties: const [],
          templates: [
            TemplateRef(
              id: templateId,
              crop: Crop.rice,
              plantingMethod: PlantingMethod.transplanted,
              source: ReferenceSource.published,
              sourceAttribution: 'PhilRice 2026 update',
              steps: [
                TemplateStepRef(
                  daysAfterPlanting: 0,
                  growthStage: 'Basal',
                  product: 'Complete 14-14-14',
                  ratePerHectare: Grams.fromKg(90),
                  sortOrder: 0,
                ),
              ],
            ),
          ],
        ),
      );

      final after = (await templates.byId(templateId))!;
      expect(
        after.steps.single.ratePerHectare.formatKg(),
        '120.0',
        reason: 'a routine refresh must not discard the agriculturist\'s advice',
      );
      expect(after.source, ReferenceSource.farmer);
    });

    test('an untouched template IS updated by a newer bundle', () async {
      await ReferenceSeeder(db).apply(
        ReferenceBundle(
          version: 2,
          publishedAt: DateTime.utc(2026, 4, 1),
          isPlaceholder: false,
          varieties: const [],
          templates: [
            TemplateRef(
              id: templateId,
              crop: Crop.rice,
              plantingMethod: PlantingMethod.transplanted,
              source: ReferenceSource.published,
              sourceAttribution: 'PhilRice 2026 update',
              steps: [
                TemplateStepRef(
                  daysAfterPlanting: 0,
                  growthStage: 'Basal',
                  product: 'Complete 14-14-14',
                  ratePerHectare: Grams.fromKg(90),
                  sortOrder: 0,
                ),
              ],
            ),
          ],
        ),
      );

      final after = (await templates.byId(templateId))!;
      expect(after.steps.single.ratePerHectare.formatKg(), '90.0');
      expect(after.source, ReferenceSource.published);
    });
  });

  group('FR-010 — custom varieties', () {
    test('a custom variety is usable and marked as the farmer\'s', () async {
      final id = await templates.createVariety(
        name: 'Local palay',
        crop: Crop.rice,
        maturityDays: 95,
      );

      final row = await (db.select(db.varieties)..where((v) => v.id.equals(id)))
          .getSingle();
      expect(row.name, 'Local palay');
      expect(row.maturityDays, 95);
      expect(row.source, SourceDb.farmer);
    });

    test('maturity may be unknown', () async {
      // spec edge case: the farmer then enters the expected harvest date.
      final id = await templates.createVariety(
        name: 'Unknown local',
        crop: Crop.corn,
        maturityDays: null,
      );
      final row = await (db.select(db.varieties)..where((v) => v.id.equals(id)))
          .getSingle();
      expect(row.maturityDays, isNull);
    });
  });

  group('FR-023 — editing one cropping\'s schedule only', () {
    test('adding a step to a cropping does not touch the template', () async {
      final croppingId = await startCropping();
      await applications.addStep(
        croppingId: croppingId,
        daysAfterPlanting: 21,
        growthStage: 'Panicle initiation',
        product: 'Muriate of Potash 0-0-60',
        ratePerHectare: Grams.fromKg(40),
        sortOrder: 1,
      );

      expect(await applications.forCropping(croppingId), hasLength(2));
      // A farmer who applied something different this one season should not
      // have that become their standing recommendation.
      expect((await templates.byId(templateId))!.steps, hasLength(1));
      expect((await templates.byId(templateId))!.source, ReferenceSource.seed);
    });

    test('removing a step from a cropping leaves the template intact', () async {
      final croppingId = await startCropping();
      final schedule = await applications.forCropping(croppingId);
      await applications.delete(schedule.single.id);

      expect(await applications.forCropping(croppingId), isEmpty);
      expect((await templates.byId(templateId))!.steps, hasLength(1));
    });

    test('a later cropping still gets the untouched template', () async {
      final first = await startCropping();
      await applications.delete(
        (await applications.forCropping(first)).single.id,
      );

      final field = await fields.create(
        name: 'Field 2',
        area: SquareMetres.parseHectares('1'),
      );
      final second = await croppings.start(
        fieldId: field.id,
        crop: Crop.rice,
        varietyId: 'v1',
        varietyMaturityDays: 110,
        plantingMethod: PlantingMethod.transplanted,
        growingSeason: GrowingSeason.dry,
        plantingDate: today,
        today: today,
      );
      expect(await applications.forCropping(second.id), hasLength(1));
    });
  });
}
