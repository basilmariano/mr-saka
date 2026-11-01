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

/// quickstart.md Scenario 3 — the feature's sharpest correctness risk.
///
/// A field can hold one cropping in the ground AND one harvested but not yet closed
/// (FR-008a). Logging "hauling on Field 1" is therefore ambiguous, and FR-031b says
/// the app "MUST NOT silently default to either".
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
  });
  tearDown(() => db.close());

  Widget harness() => ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const SakaApp(home: FieldsScreen()),
      );

  testWidgets('a cropping in the ground blocks replanting, and says which one',
      (tester) async {
    await db.into(db.croppings).insert(CroppingsCompanion.insert(
        id: 'c1', fieldId: 'f1', crop: CropDb.rice, varietyId: 'v1',
        plantingMethod: PlantingMethodDb.transplanted,
        growingSeason: SeasonDb.wet, plantingDate: today,
        status: StatusDb.growing, updatedAt: DateTime.now().toUtc()));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
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

    // spec edge case "Field already busy": the refusal names the cropping.
    expect(find.text('This field already has a cropping'), findsOneWidget);
    expect(find.textContaining('Rice'), findsWidgets);
  });

  testWidgets('replanting after harvest is allowed, and prompts to close',
      (tester) async {
    await db.into(db.croppings).insert(CroppingsCompanion.insert(
        id: 'c1', fieldId: 'f1', crop: CropDb.rice, varietyId: 'v1',
        plantingMethod: PlantingMethodDb.transplanted,
        growingSeason: SeasonDb.wet, plantingDate: today,
        status: StatusDb.harvested, updatedAt: DateTime.now().toUtc()));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
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

    // FR-008b: prompted, never forced.
    expect(find.text('Close the previous cropping?'), findsOneWidget);
    await tester.tap(find.text('Leave it open'));
    await tester.pumpAndSettle();

    // Both croppings now exist and both are open.
    final croppings = await db.select(db.croppings).get();
    expect(croppings, hasLength(2));
    expect(
      croppings.where((c) => c.status != StatusDb.closed).length,
      2,
      reason: 'the harvested one stays open so sales can still be recorded',
    );
  });

  testWidgets('an expense on a field with two open croppings asks which one',
      (tester) async {
    await db.into(db.croppings).insert(CroppingsCompanion.insert(
        id: 'c1', fieldId: 'f1', crop: CropDb.rice, varietyId: 'v1',
        plantingMethod: PlantingMethodDb.transplanted,
        growingSeason: SeasonDb.wet, plantingDate: today,
        status: StatusDb.harvested, updatedAt: DateTime.now().toUtc()));
    await db.into(db.croppings).insert(CroppingsCompanion.insert(
        id: 'c2', fieldId: 'f1', crop: CropDb.corn, varietyId: 'v1',
        plantingMethod: PlantingMethodDb.directSeeded,
        growingSeason: SeasonDb.dry, plantingDate: '2026-07-01',
        status: StatusDb.planted, updatedAt: DateTime.now().toUtc()));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Field 1'));
    await tester.pumpAndSettle();

    // FR-031c: each is identified by crop, season, and planting date — never by
    // field alone, which would be the same for both.
    expect(find.textContaining('Rice, Wet season, planted 2026-03-01'),
        findsOneWidget);
    expect(find.textContaining('Corn, Dry season, planted 2026-07-01'),
        findsOneWidget);
  });
}
