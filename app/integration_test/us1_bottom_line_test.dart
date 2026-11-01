import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:saka/data/local/database.dart';
import 'package:saka/data/local/tables.dart';
import 'package:saka/ui/common/app.dart';
import 'package:saka/ui/common/providers.dart';
import 'package:saka/ui/fields/fields_screen.dart';

/// quickstart.md Scenario 1, driven through the real UI on a real device.
///
/// RUN ON HARDWARE:
///   flutter test integration_test --device-id <device>
///
/// The same journey is covered headlessly at the repository layer in
/// test/data/us1_journey_test.dart and at the widget layer in
/// test/ui/us1_widget_test.dart. This file exists because those cannot prove the
/// flow works on a real phone — which is what the farmer actually uses.
/// Enters text into a field that may be below the fold.
///
/// These forms are taller than a phone screen, and a ListView does not build its
/// off-screen children — so a finder for a field further down resolves to nothing
/// until it is scrolled into view.
Future<void> enterTextScrolled(
  WidgetTester tester,
  Key key,
  String text,
) async {
  final finder = find.byKey(key);
  if (finder.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      finder,
      find.byType(Scrollable).first,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
  }
  await tester.enterText(finder, text);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SakaDatabase db;

  setUp(() async {
    db = SakaDatabase.memory();
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
  });
  tearDown(() => db.close());

  Widget harness() => ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const SakaApp(home: FieldsScreen()),
      );

  testWidgets('a farmer runs a full cropping and sees the bottom line',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // 1. Add "Field 1", 2.5 ha.
    await tester.tap(find.byIcon(FIcons.plus).last);
    await tester.pumpAndSettle();
    await enterTextScrolled(tester, const Key('field-name'), 'Field 1');
    await enterTextScrolled(tester, const Key('field-area'), '2.5');
    await tester.tap(find.byKey(const Key('save-button')));
    await tester.pumpAndSettle();
    expect(find.text('Field 1'), findsOneWidget);

    // 2. Open the field and start a cropping.
    await tester.tap(find.text('Field 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-start-cropping')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('variety-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NSIC Rc222').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start-cropping-button')));
    await tester.pumpAndSettle();

    // 3. Open the cropping and log three expenses.
    await tester.tap(find.textContaining('Rice').first);
    await tester.pumpAndSettle();

    for (final (amount, category) in [
      ('3500', 'labor'),
      ('12000', 'landPreparation'),
      ('8000', 'seeds'),
    ]) {
      await tester.tap(find.byKey(const ValueKey('tab-Expenses')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-Expenses')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();
      await enterTextScrolled(tester, const Key('expense-amount'), amount);
      await tester.tap(find.byKey(ValueKey('category-$category')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-button')));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('23,500.00'), findsWidgets);

    // 4. Record the harvest: 100 sacks x 50 kg wet.
    await tester.tap(find.byKey(const ValueKey('tab-Harvest')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record harvest'));
    await tester.pumpAndSettle();
    await enterTextScrolled(tester, const Key('harvest-sacks'), '100');
    await tester.tap(find.byKey(const Key('save-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('5.00'), findsWidgets);

    // 5. Record a sale: 4,000 kg at PHP 20.00/kg.
    await tester.tap(find.text('Record a sale'));
    await tester.pumpAndSettle();
    await enterTextScrolled(tester, const Key('sale-quantity'), '4000');
    await enterTextScrolled(tester, const Key('sale-price'), '20');
    await enterTextScrolled(tester, const Key('sale-buyer'), 'Trader');
    await tester.tap(find.byKey(const Key('save-button')));
    await tester.pumpAndSettle();

    // 6. The result: every figure, with no manual arithmetic by the farmer.
    await tester.tap(find.byKey(const ValueKey('tab-Result')));
    await tester.pumpAndSettle();

    expect(find.textContaining('23,500.00'), findsWidgets); // spent
    expect(find.textContaining('80,000.00'), findsWidgets); // earned
    expect(find.textContaining('56,500.00'), findsWidgets); // profit
    expect(find.textContaining('5.00'), findsWidgets); // tons
    expect(find.textContaining('2.00'), findsWidgets); // tons per hectare
    expect(find.textContaining('4.70'), findsWidgets); // cost per kg
    expect(find.textContaining('1,000.0 kg'), findsWidgets); // unsold
    expect(find.text('Provisional'), findsOneWidget); // FR-042a
  });

  testWidgets('post-harvest hauling moves the provisional profit, then closing',
      (tester) async {
    // quickstart.md Scenario 2. Seeded directly so the journey above is not
    // repeated; what is under test is the post-harvest window and closing.
    const today = '2026-03-01';
    await db.into(db.fields).insert(FieldsCompanion.insert(
        id: 'f1', name: 'Field 1', areaSqm: 25000,
        updatedAt: DateTime.now().toUtc()));
    await db.into(db.croppings).insert(CroppingsCompanion.insert(
        id: 'c1', fieldId: 'f1', crop: CropDb.rice, varietyId: 'v1',
        plantingMethod: PlantingMethodDb.transplanted,
        growingSeason: SeasonDb.wet, plantingDate: today,
        status: StatusDb.harvested, updatedAt: DateTime.now().toUtc()));
    await db.into(db.harvests).insert(HarvestsCompanion.insert(
        id: 'h1', croppingId: 'c1', date: today, totalWetGrams: 5000000,
        updatedAt: DateTime.now().toUtc()));
    await db.into(db.sales).insert(SalesCompanion.insert(
        id: 's1', croppingId: 'c1', quantityGrams: 4000000,
        pricePerKgCentavos: 2000, buyer: 'Trader', date: today,
        updatedAt: DateTime.now().toUtc()));
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
        id: 'e1', croppingId: 'c1', date: today,
        category: CategoryDb.landPreparation, amountCentavos: 2350000,
        updatedAt: DateTime.now().toUtc()));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Field 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Rice').first);
    await tester.pumpAndSettle();

    // FR-031a: a cost dated after the harvest is accepted without warning.
    await tester.tap(find.byKey(const ValueKey('tab-Expenses')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();
    await enterTextScrolled(tester, const Key('expense-amount'), '4000');
    await tester.tap(find.byKey(const ValueKey('category-hauling')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tab-Result')));
    await tester.pumpAndSettle();
    expect(find.textContaining('27,500.00'), findsWidgets);
    expect(find.textContaining('52,500.00'), findsWidgets);
    expect(find.text('Provisional'), findsOneWidget);

    // FR-012c: closing with stock unsold warns and names the quantity.
    await tester.tap(find.byIcon(FIcons.circleCheck));
    await tester.pumpAndSettle();
    expect(find.textContaining('1,000.0'), findsWidgets);
    await tester.tap(find.text('Close cropping'));
    await tester.pumpAndSettle();

    expect(find.text('Final'), findsOneWidget);
  });
}
