import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:saka/data/local/database.dart';
import 'package:saka/data/local/tables.dart';
import 'package:saka/ui/common/app.dart';
import 'package:saka/ui/common/providers.dart';
import 'package:saka/ui/fields/fields_screen.dart';

/// quickstart.md Scenario 9 — wet and dry weight.
///
/// Harvest 5,000 kg wet, dry it to 4,200 kg, sell 4,000 kg dry. Remaining must read
/// 200 kg dry, NOT the 1,000 kg that subtracting dry from wet would give (FR-037a).
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
  const today = '2026-03-01';

  setUp(() async {
    db = SakaDatabase.memory();
    await db.into(db.varieties).insert(VarietiesCompanion.insert(
        id: 'v1', name: 'NSIC Rc222', crop: CropDb.rice,
        maturityDays: const Value(110), source: SourceDb.seed,
        updatedAt: DateTime.now().toUtc()));
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
  });
  tearDown(() => db.close());

  Widget harness() => ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const SakaApp(home: FieldsScreen()),
      );

  Future<void> openSaleForm(WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Field 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Rice').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-Harvest')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record a sale'));
    await tester.pumpAndSettle();
  }

  testWidgets('selling dry asks for the dried weight before the sale',
      (tester) async {
    await openSaleForm(tester);

    expect(find.text('Are you selling this wet or dry?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('basis-dry')));
    await tester.pumpAndSettle();

    // FR-034b: the app asks rather than guessing a wet-to-dry conversion.
    expect(find.text('Dried weight'), findsOneWidget);
    expect(find.byKey(const Key('sale-dried-weight')), findsOneWidget);
  });

  testWidgets('remaining counts down from the dried weight, not the harvest',
      (tester) async {
    await openSaleForm(tester);
    await tester.tap(find.byKey(const Key('basis-dry')));
    await tester.pumpAndSettle();

    await enterTextScrolled(tester, const Key('sale-dried-weight'), '4200');
    await enterTextScrolled(tester, const Key('sale-quantity'), '4000');
    await enterTextScrolled(tester, const Key('sale-price'), '23');
    await enterTextScrolled(tester, const Key('sale-buyer'), 'Trader');
    await tester.tap(find.byKey(const Key('save-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tab-Result')));
    await tester.pumpAndSettle();

    expect(find.textContaining('200.0 kg dry'), findsOneWidget);
    expect(find.textContaining('1,000.0 kg'), findsNothing);
    // Yield stays on the fresh-weight basis so croppings remain comparable.
    expect(find.textContaining('5.00'), findsWidgets);
  });

  testWidgets('a sale larger than what is left is refused with the amount',
      (tester) async {
    await openSaleForm(tester);
    await tester.tap(find.byKey(const Key('basis-wet')));
    await tester.pumpAndSettle();

    await enterTextScrolled(tester, const Key('sale-quantity'), '5001');
    await enterTextScrolled(tester, const Key('sale-price'), '20');
    await enterTextScrolled(tester, const Key('sale-buyer'), 'Trader');
    await tester.tap(find.byKey(const Key('save-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('more than the'), findsOneWidget);
  });
}
