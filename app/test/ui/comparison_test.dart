import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saka/data/local/database.dart';
import 'package:saka/data/local/repositories/cropping_repository.dart';
import 'package:saka/data/local/repositories/expense_repository.dart';
import 'package:saka/data/local/repositories/field_repository.dart';
import 'package:saka/data/local/repositories/harvest_repository.dart';
import 'package:saka/data/local/repositories/sale_repository.dart';
import 'package:saka/data/local/tables.dart';
import 'package:saka/domain/model/calendar_date.dart';
import 'package:saka/domain/model/centavos.dart';
import 'package:saka/domain/model/enums.dart';
import 'package:saka/domain/model/grams.dart';
import 'package:saka/domain/model/square_metres.dart';
import 'package:saka/ui/common/app.dart';
import 'package:saka/ui/common/providers.dart';
import 'package:saka/ui/results/comparison_screen.dart';

/// User Story 4 — FR-043.

/// The comparison cards, excluding the filter chips.
///
/// Field and season names appear in BOTH the chips and the cards, so an unscoped
/// `find.text` matches twice and says nothing about what is actually listed.
Finder comparisonCards() => find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('comparison-'),
    );

Finder inCards(Finder matching) =>
    find.descendant(of: comparisonCards(), matching: matching);

Future<void> disposeTree(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SakaDatabase db;
  late FieldRepository fields;
  late CroppingRepository croppings;
  late ExpenseRepository expenses;
  late HarvestRepository harvests;
  late SaleRepository sales;

  const today = CalendarDate(2026, 3, 1);

  setUp(() async {
    db = SakaDatabase.memory();
    fields = FieldRepository(db);
    croppings = CroppingRepository(db);
    expenses = ExpenseRepository(db);
    harvests = HarvestRepository(db);
    sales = SaleRepository(db);

    for (final (id, name) in [('v1', 'NSIC Rc222'), ('v2', 'Corn hybrid')]) {
      await db.into(db.varieties).insert(
            VarietiesCompanion.insert(
              id: id,
              name: name,
              crop: id == 'v1' ? CropDb.rice : CropDb.corn,
              maturityDays: const Value(110),
              source: SourceDb.seed,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
    }
  });
  tearDown(() => db.close());

  Widget harness() => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 1)),
        ],
        child: const SakaApp(home: ComparisonScreen()),
      );

  void tallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// A finished cropping: expenses, harvest, sale, closed.
  Future<void> seedClosed({
    required String fieldName,
    required Crop crop,
    required GrowingSeason season,
    required CalendarDate plantingDate,
    required int expensePesos,
    required int harvestKg,
    required int salePricePerKg,
    String areaHa = '2.5',
  }) async {
    final field = await fields.create(
      name: fieldName,
      area: SquareMetres.parseHectares(areaHa),
    );
    final cropping = await croppings.start(
      fieldId: field.id,
      crop: crop,
      varietyId: crop == Crop.rice ? 'v1' : 'v2',
      varietyMaturityDays: 110,
      plantingMethod: crop == Crop.rice
          ? PlantingMethod.transplanted
          : PlantingMethod.directSeeded,
      growingSeason: season,
      plantingDate: plantingDate,
      today: plantingDate,
    );
    await expenses.create(
      croppingId: cropping.id,
      date: plantingDate,
      category: ExpenseCategory.seeds,
      amount: Centavos.fromPesos(expensePesos),
    );
    await harvests.record(
      croppingId: cropping.id,
      date: plantingDate.addDays(110),
      totalWet: Grams.fromKg(harvestKg),
    );
    await croppings.markHarvested(cropping.id);
    final refreshed = (await croppings.byId(cropping.id))!;
    await sales.record(
      cropping: refreshed,
      quantity: Grams.fromKg(harvestKg),
      pricePerKg: Centavos.fromPesos(salePricePerKg),
      buyer: 'Trader',
      date: plantingDate.addDays(115),
    );
    await croppings.close(cropping.id);
  }

  testWidgets('empty state when there is nothing to compare', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('No croppings to compare yet'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('lists every cropping with its figures', (tester) async {
    // FR-043: field, crop, variety, season, planting date, expenses, revenue,
    // profit, tons per hectare, cost per kilogram.
    tallViewport(tester);
    await seedClosed(
      fieldName: 'Field 1',
      crop: Crop.rice,
      season: GrowingSeason.wet,
      plantingDate: today,
      expensePesos: 23500,
      harvestKg: 5000,
      salePricePerKg: 20,
    );

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(inCards(find.text('Field 1')), findsOneWidget);
    expect(find.textContaining('NSIC Rc222'), findsOneWidget);
    expect(inCards(find.textContaining('Wet season')), findsOneWidget);
    expect(find.textContaining('Transplanted'), findsOneWidget);
    expect(find.textContaining('23,500.00'), findsOneWidget); // spent
    expect(find.textContaining('100,000.00'), findsOneWidget); // earned
    expect(find.textContaining('76,500.00'), findsOneWidget); // profit
    expect(find.textContaining('2.00'), findsOneWidget); // tons per hectare
    expect(find.textContaining('4.70'), findsOneWidget); // cost per kg
    await disposeTree(tester);
  });

  testWidgets('marks the best profit among comparable croppings',
      (tester) async {
    tallViewport(tester);
    await seedClosed(
      fieldName: 'Field 1',
      crop: Crop.rice,
      season: GrowingSeason.wet,
      plantingDate: today,
      expensePesos: 20000,
      harvestKg: 5000,
      salePricePerKg: 20,
    );
    await seedClosed(
      fieldName: 'Field 2',
      crop: Crop.rice,
      season: GrowingSeason.dry,
      plantingDate: const CalendarDate(2026, 1, 1),
      expensePesos: 20000,
      harvestKg: 3000,
      salePricePerKg: 20,
    );

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Best profit'), findsOneWidget);
    expect(find.text('2 croppings'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('filters to a single field', (tester) async {
    tallViewport(tester);
    await seedClosed(
      fieldName: 'Field 1',
      crop: Crop.rice,
      season: GrowingSeason.wet,
      plantingDate: today,
      expensePesos: 20000,
      harvestKg: 5000,
      salePricePerKg: 20,
    );
    await seedClosed(
      fieldName: 'Field 2',
      crop: Crop.rice,
      season: GrowingSeason.dry,
      plantingDate: const CalendarDate(2026, 1, 1),
      expensePesos: 20000,
      harvestKg: 3000,
      salePricePerKg: 20,
    );

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('2 croppings'), findsOneWidget);

    final fieldId = (await fields.listActive())
        .firstWhere((f) => f.name == 'Field 1')
        .id;
    await tester.tap(find.byKey(ValueKey('filter-field-$fieldId')));
    await tester.pumpAndSettle();

    expect(find.text('1 cropping'), findsOneWidget);
    expect(comparisonCards(), findsOneWidget);
    expect(inCards(find.text('Field 1')), findsOneWidget);
    expect(inCards(find.text('Field 2')), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('filters to a single season across all fields', (tester) async {
    tallViewport(tester);
    await seedClosed(
      fieldName: 'Field 1',
      crop: Crop.rice,
      season: GrowingSeason.wet,
      plantingDate: today,
      expensePesos: 20000,
      harvestKg: 5000,
      salePricePerKg: 20,
    );
    await seedClosed(
      fieldName: 'Field 2',
      crop: Crop.rice,
      season: GrowingSeason.dry,
      plantingDate: const CalendarDate(2026, 1, 1),
      expensePesos: 20000,
      harvestKg: 3000,
      salePricePerKg: 20,
    );

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-season-dry')));
    await tester.pumpAndSettle();

    expect(find.text('1 cropping'), findsOneWidget);
    expect(comparisonCards(), findsOneWidget);
    expect(inCards(find.text('Field 2')), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('filters to a single crop', (tester) async {
    tallViewport(tester);
    await seedClosed(
      fieldName: 'Rice field',
      crop: Crop.rice,
      season: GrowingSeason.wet,
      plantingDate: today,
      expensePesos: 20000,
      harvestKg: 5000,
      salePricePerKg: 20,
    );
    await seedClosed(
      fieldName: 'Corn field',
      crop: Crop.corn,
      season: GrowingSeason.dry,
      plantingDate: const CalendarDate(2026, 1, 1),
      expensePesos: 15000,
      harvestKg: 4000,
      salePricePerKg: 18,
    );

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-crop-corn')));
    await tester.pumpAndSettle();

    expect(find.text('1 cropping'), findsOneWidget);
    expect(comparisonCards(), findsOneWidget);
    expect(inCards(find.text('Corn field')), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('says so when filters exclude everything', (tester) async {
    tallViewport(tester);
    await seedClosed(
      fieldName: 'Rice field',
      crop: Crop.rice,
      season: GrowingSeason.wet,
      plantingDate: today,
      expensePesos: 20000,
      harvestKg: 5000,
      salePricePerKg: 20,
    );

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-crop-corn')));
    await tester.pumpAndSettle();

    expect(find.text('No croppings match these filters'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('an unharvested cropping shows no profit and is not a loss',
      (tester) async {
    // FR-042 holds in the comparison too: the absence of revenue must not be
    // presented as a loss, or an in-progress cropping would always look worst.
    tallViewport(tester);
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
    await expenses.create(
      croppingId: cropping.id,
      date: today,
      category: ExpenseCategory.seeds,
      amount: Centavos.fromPesos(12000),
    );

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.textContaining('12,000.00'), findsOneWidget);
    expect(find.text('Loss'), findsNothing);
    expect(find.text('Best profit'), findsNothing);
    expect(find.text('In progress'), findsWidgets);
    await disposeTree(tester);
  });
}
