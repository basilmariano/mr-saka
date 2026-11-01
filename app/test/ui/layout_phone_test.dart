import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saka/data/local/database.dart';
import 'package:saka/data/local/tables.dart';
import 'package:saka/ui/account/settings_screen.dart';
import 'package:saka/ui/account/sign_in_screen.dart';
import 'package:saka/ui/common/app.dart';
import 'package:saka/ui/common/providers.dart';
import 'package:saka/ui/croppings/cropping_detail.dart';
import 'package:saka/ui/croppings/start_cropping.dart';
import 'package:saka/ui/fertilizer/template_editor.dart';
import 'package:saka/ui/fields/field_detail.dart';
import 'package:saka/ui/fields/field_form.dart';
import 'package:saka/ui/fields/fields_screen.dart';
import 'package:saka/ui/home/home_screen.dart';
import 'package:saka/ui/results/comparison_screen.dart';

/// Every screen must lay out without overflowing at real phone width.
///
/// This suite exists because four separate layout bugs reached a device while
/// 169 headless tests passed: the default 800x600 test surface is wider and
/// taller than any phone, so nothing that only overflows on a handset shows up.
///
/// Forui is the recurring cause — FButton and FTabs lay their children out at
/// natural size inside their own Rows and neither shrinks nor ellipsises, so a
/// label that fits in English can still break the layout. Phase 2's local
/// language will have longer strings than English, which makes this suite the
/// thing standing between that translation and a broken screen.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // iPhone 16 logical size. Narrower than most Android handsets in the target
  // market, so passing here is the stricter case.
  const phone = Size(393 * 3, 852 * 3);

  late SakaDatabase db;

  setUp(() async {
    db = SakaDatabase.memory();
    const today = '2026-03-01';
    await db.into(db.varieties).insert(VarietiesCompanion.insert(
        id: 'v1', name: 'NSIC Rc222', crop: CropDb.rice,
        maturityDays: const Value(110), source: SourceDb.seed,
        sourceAttribution: const Value('PhilRice test fixture'),
        updatedAt: DateTime.now().toUtc()));
    await db.into(db.fertilizerTemplates).insert(
        FertilizerTemplatesCompanion.insert(
            id: 't1', crop: CropDb.rice,
            plantingMethod: PlantingMethodDb.transplanted,
            source: SourceDb.seed, updatedAt: DateTime.now().toUtc()));
    await db.into(db.fertilizerTemplateSteps).insert(
        FertilizerTemplateStepsCompanion.insert(
            id: 's1', templateId: 't1', daysAfterPlanting: 14,
            growthStage: 'Early tillering', product: 'Urea 46-0-0',
            ratePerHectareGrams: 100000, sortOrder: 0,
            updatedAt: DateTime.now().toUtc()));
    await db.into(db.fields).insert(FieldsCompanion.insert(
        id: 'f1', name: 'Field 1', areaSqm: 25000,
        updatedAt: DateTime.now().toUtc()));
    await db.into(db.croppings).insert(CroppingsCompanion.insert(
        id: 'c1', fieldId: 'f1', crop: CropDb.rice, varietyId: 'v1',
        plantingMethod: PlantingMethodDb.transplanted,
        growingSeason: SeasonDb.wet, plantingDate: today,
        status: StatusDb.planted, updatedAt: DateTime.now().toUtc()));
    await db.into(db.scheduledApplications).insert(
        ScheduledApplicationsCompanion.insert(
            id: 'a1', croppingId: 'c1', daysAfterPlanting: 14,
            growthStage: 'Early tillering', recommendedProduct: 'Urea 46-0-0',
            ratePerHectareGrams: 100000, sortOrder: 0,
            state: AppStateDb.pending, updatedAt: DateTime.now().toUtc()));
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
        id: 'e1', croppingId: 'c1', date: today,
        category: CategoryDb.landPreparation, amountCentavos: 1200000,
        updatedAt: DateTime.now().toUtc()));
  });
  tearDown(() => db.close());

  /// Pumps [screen] and fails if anything overflows.
  Future<void> expectNoOverflow(
    WidgetTester tester,
    Widget screen, {
    Size size = phone,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final captured = <FlutterErrorDetails>[];
    final original = FlutterError.onError;
    FlutterError.onError = captured.add;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => DateTime(2026, 3, 1)),
      ],
      child: SakaApp(home: screen),
    ));
    await tester.pumpAndSettle();
    FlutterError.onError = original;

    final overflows = captured
        .where((d) => d.exception.toString().contains('overflowed'))
        .map((d) => d.exception.toString())
        .toList();
    expect(overflows, isEmpty, reason: overflows.join('\n'));

    // Forui's FTappable and drift's streams both schedule timers on teardown.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  final screens = <String, Widget>{
    'home': const HomeScreen(),
    'fields': const FieldsScreen(),
    'field form': const FieldForm(),
    'field detail': const FieldDetail(fieldId: 'f1'),
    'start cropping': const StartCroppingScreen(fieldId: 'f1'),
    'cropping detail': const CroppingDetail(croppingId: 'c1'),
    'comparison': const ComparisonScreen(),
    'templates': const TemplateListScreen(),
    'template editor': const TemplateEditorScreen(templateId: 't1'),
    'settings': const SettingsScreen(),
    'sign in': const SignInScreen(),
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key} lays out at phone width', (tester) async {
      await expectNoOverflow(tester, entry.value);
    });
  }

  // A screen is also laid out in very little space: mid-navigation-transition,
  // and with the keyboard up. A device run caught an empty state overflowing a
  // 106pt box during a push, which the full-height cases above all missed.
  const squeezed = Size(393 * 3, 320 * 3);

  for (final entry in screens.entries) {
    testWidgets('${entry.key} survives a squeezed viewport', (tester) async {
      await expectNoOverflow(tester, entry.value, size: squeezed);
    });
  }
}
