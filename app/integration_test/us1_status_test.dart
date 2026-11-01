import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:saka/data/local/database.dart';
import 'package:saka/data/local/repositories/cropping_repository.dart';
import 'package:saka/data/local/tables.dart';
import 'package:saka/domain/model/calendar_date.dart';
import 'package:saka/domain/model/enums.dart';
import 'package:saka/ui/common/app.dart';
import 'package:saka/ui/common/providers.dart';
import 'package:saka/ui/fields/fields_screen.dart';

/// quickstart.md Scenario 10 — the planted -> growing transition.
///
/// FR-011a: whichever comes first, the first fertilizer application marked done or
/// 10 days after planting. FR-011b: decided on the device, with no network call.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SakaDatabase db;
  late CroppingRepository croppings;
  const planting = CalendarDate(2026, 3, 1);

  setUp(() async {
    db = SakaDatabase.memory();
    croppings = CroppingRepository(db);
    await db.into(db.varieties).insert(VarietiesCompanion.insert(
        id: 'v1', name: 'NSIC Rc222', crop: CropDb.rice,
        maturityDays: const Value(110), source: SourceDb.seed,
        updatedAt: DateTime.now().toUtc()));
    await db.into(db.fields).insert(FieldsCompanion.insert(
        id: 'f1', name: 'Field 1', areaSqm: 25000,
        updatedAt: DateTime.now().toUtc()));
  });
  tearDown(() => db.close());

  Widget harness(DateTime now) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => now),
        ],
        child: const SakaApp(home: FieldsScreen()),
      );

  Future<String> seedCropping(CalendarDate plantingDate, DateTime now) async {
    final cropping = await croppings.start(
      fieldId: 'f1',
      crop: Crop.rice,
      varietyId: 'v1',
      varietyMaturityDays: 110,
      plantingMethod: PlantingMethod.transplanted,
      growingSeason: GrowingSeason.wet,
      plantingDate: plantingDate,
      today: CalendarDate.fromDateTime(now),
    );
    return cropping.id;
  }

  testWidgets('a cropping planted today shows as Planted', (tester) async {
    await seedCropping(planting, DateTime(2026, 3, 1));
    await tester.pumpWidget(harness(DateTime(2026, 3, 1)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Field 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Planted'), findsWidgets);
  });

  testWidgets('it shows as Growing once 10 days have passed, offline',
      (tester) async {
    final id = await seedCropping(planting, DateTime(2026, 3, 1));
    // FR-011b: a date comparison on the device. No network involved.
    await croppings.refreshStatuses(const CalendarDate(2026, 3, 11));

    await tester.pumpWidget(harness(DateTime(2026, 3, 11)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Field 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Rice').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Growing'), findsWidgets);
    expect((await croppings.byId(id))!.status, CroppingStatus.growing);
  });

  testWidgets('a cropping backdated more than 10 days starts as Growing',
      (tester) async {
    // FR-011c.
    final id = await seedCropping(
      const CalendarDate(2026, 2, 14),
      DateTime(2026, 3, 1),
    );
    expect((await croppings.byId(id))!.status, CroppingStatus.growing);

    await tester.pumpWidget(harness(DateTime(2026, 3, 1)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Field 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Growing'), findsWidgets);
  });
}
