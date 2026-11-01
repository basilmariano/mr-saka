import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saka/data/local/database.dart';
import 'package:saka/data/local/repositories/application_repository.dart';
import 'package:saka/data/local/repositories/cropping_repository.dart';
import 'package:saka/data/local/repositories/expense_repository.dart';
import 'package:saka/data/local/repositories/field_repository.dart';
import 'package:saka/data/local/repositories/harvest_repository.dart';
import 'package:saka/data/local/tables.dart';
import 'package:saka/data/reference/template_lookup.dart';
import 'package:saka/domain/model/calendar_date.dart';
import 'package:saka/domain/model/enums.dart';
import 'package:saka/domain/model/grams.dart';
import 'package:saka/domain/model/square_metres.dart';
import 'package:saka/ui/common/app.dart';
import 'package:saka/ui/common/providers.dart';
import 'package:saka/ui/home/home_screen.dart';

/// User Story 3 — FR-044 to FR-046b.

Future<void> disposeTree(WidgetTester tester) async {
  // Forui's FTappable schedules a 200ms press-feedback timer, and drift's query
  // streams schedule one on cancel. Advance past both before disposing.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SakaDatabase db;
  late FieldRepository fields;
  late CroppingRepository croppings;
  late ApplicationRepository applications;
  late HarvestRepository harvests;

  const today = CalendarDate(2026, 3, 1);
  const templateId = 'tmpl-1';

  setUp(() async {
    db = SakaDatabase.memory();
    fields = FieldRepository(db);
    final expenses = ExpenseRepository(db);
    applications = ApplicationRepository(db, expenses: expenses);
    harvests = HarvestRepository(db);
    croppings = CroppingRepository(
      db,
      applications: applications,
      templates: TemplateLookup(db),
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
            updatedAt: DateTime.now().toUtc(),
          ),
        );
    await db.into(db.fertilizerTemplateSteps).insert(
          FertilizerTemplateStepsCompanion.insert(
            id: 'step-1',
            templateId: templateId,
            daysAfterPlanting: 5,
            growthStage: 'Early tillering',
            product: 'Urea 46-0-0',
            ratePerHectareGrams: Grams.fromKg(100).value,
            sortOrder: 0,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  });
  tearDown(() => db.close());

  Widget harness({CalendarDate now = today}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => now.toDateTime()),
        ],
        child: const SakaApp(home: HomeScreen()),
      );

  void tallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<String> startCropping({
    String fieldName = 'Field 1',
    CalendarDate plantingDate = today,
    PlantingMethod method = PlantingMethod.transplanted,
  }) async {
    final field = await fields.create(
      name: fieldName,
      area: SquareMetres.parseHectares('2.5'),
    );
    final cropping = await croppings.start(
      fieldId: field.id,
      crop: Crop.rice,
      varietyId: 'v1',
      varietyMaturityDays: 110,
      plantingMethod: method,
      growingSeason: GrowingSeason.wet,
      plantingDate: plantingDate,
      today: plantingDate,
    );
    return cropping.id;
  }

  testWidgets('empty state invites the farmer in rather than showing blanks',
      (tester) async {
    // US3 acceptance scenario 4.
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('No croppings yet'), findsOneWidget);
    expect(find.text('All fields'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('shows active croppings with status and days since planting',
      (tester) async {
    // FR-044.
    tallViewport(tester);
    await startCropping();
    await tester.pumpWidget(harness(now: const CalendarDate(2026, 3, 6)));
    await tester.pumpAndSettle();

    expect(find.text('Active croppings'), findsOneWidget);
    expect(find.text('Field 1'), findsWidgets);
    expect(find.textContaining('5 days since planting'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('shows the next fertilizer application with bags to buy',
      (tester) async {
    // FR-045 and SC-004: the bag count is what the farmer acts on.
    tallViewport(tester);
    await startCropping();
    await tester.pumpWidget(harness(now: const CalendarDate(2026, 3, 3)));
    await tester.pumpAndSettle();

    expect(find.text('Fertilizer due next'), findsOneWidget);
    expect(find.textContaining('Urea 46-0-0'), findsWidgets);
    expect(find.textContaining('5.0 bags'), findsOneWidget);
    expect(find.textContaining('Due in 3 days'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('flags an overdue application', (tester) async {
    // FR-018 surfaced on the home screen — where a farmer notices one they missed.
    tallViewport(tester);
    await startCropping();
    await tester.pumpWidget(harness(now: const CalendarDate(2026, 3, 10)));
    await tester.pumpAndSettle();

    expect(find.text('Overdue'), findsOneWidget);
    expect(find.textContaining('Overdue by 4 days'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('shows an approaching harvest', (tester) async {
    // FR-046. Planted 1 March with 110 days maturity means 19 June.
    tallViewport(tester);
    await startCropping();
    await tester.pumpWidget(harness(now: const CalendarDate(2026, 6, 10)));
    await tester.pumpAndSettle();

    expect(find.text('Harvest coming up'), findsOneWidget);
    expect(find.textContaining('Harvest expected 2026-06-19'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('keeps a harvested but unclosed cropping visible with its unsold stock',
      (tester) async {
    // FR-046a: once a field is replanted it is easy to move on while sales and
    // post-harvest costs are still outstanding.
    tallViewport(tester);
    final croppingId = await startCropping();
    await harvests.record(
      croppingId: croppingId,
      date: const CalendarDate(2026, 6, 19),
      totalWet: Grams.fromKg(5000),
    );
    await croppings.markHarvested(croppingId);

    await tester.pumpWidget(harness(now: const CalendarDate(2026, 6, 20)));
    await tester.pumpAndSettle();

    expect(find.text('Harvested, not yet closed'), findsOneWidget);
    expect(find.textContaining('5,000.0 kg wet still unsold'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('shows both croppings distinctly when a field holds two',
      (tester) async {
    // FR-046b. One harvested but open, one newly in the ground on the same field.
    tallViewport(tester);
    final first = await startCropping();
    await harvests.record(
      croppingId: first,
      date: const CalendarDate(2026, 6, 19),
      totalWet: Grams.fromKg(5000),
    );
    await croppings.markHarvested(first);

    final field = (await fields.listActive()).single;
    await croppings.start(
      fieldId: field.id,
      crop: Crop.rice,
      varietyId: 'v1',
      varietyMaturityDays: 110,
      plantingMethod: PlantingMethod.transplanted,
      growingSeason: GrowingSeason.dry,
      plantingDate: const CalendarDate(2026, 7, 1),
      today: const CalendarDate(2026, 7, 1),
    );

    await tester.pumpWidget(harness(now: const CalendarDate(2026, 7, 2)));
    await tester.pumpAndSettle();

    // Identified by season and planting date, never by field alone.
    expect(find.textContaining('Wet season, planted 2026-03-01'), findsOneWidget);
    expect(find.textContaining('Dry season, planted 2026-07-01'), findsOneWidget);
    expect(find.text('Active croppings'), findsOneWidget);
    expect(find.text('Harvested, not yet closed'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('a closed cropping drops off the home screen entirely',
      (tester) async {
    tallViewport(tester);
    final croppingId = await startCropping();
    await harvests.record(
      croppingId: croppingId,
      date: const CalendarDate(2026, 6, 19),
      totalWet: Grams.fromKg(5000),
    );
    await croppings.markHarvested(croppingId);
    await croppings.close(croppingId);

    await tester.pumpWidget(harness(now: const CalendarDate(2026, 6, 20)));
    await tester.pumpAndSettle();

    expect(find.text('No croppings yet'), findsOneWidget);
    await disposeTree(tester);
  });
}
