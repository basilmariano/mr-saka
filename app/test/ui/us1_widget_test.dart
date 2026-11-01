import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saka/data/local/database.dart';
import 'package:saka/data/local/repositories/result_repository.dart';
import 'package:saka/domain/calc/money_calc.dart';
import 'package:saka/domain/model/centavos.dart';
import 'package:saka/domain/model/entities.dart';
import 'package:saka/domain/model/enums.dart';
import 'package:saka/domain/model/grams.dart';
import 'package:saka/domain/model/square_metres.dart';
import 'package:saka/domain/rules/weight_basis.dart';
import 'package:saka/ui/common/app.dart';
import 'package:saka/ui/common/providers.dart';
import 'package:saka/ui/fields/fields_screen.dart';
import 'package:saka/ui/results/cropping_result.dart';

/// User Story 1 at the widget layer.
///
/// These cover rendering and input validation with providers overridden, so they are
/// fast and deterministic. The data layer behind them is covered end to end against a
/// real database in test/data/us1_journey_test.dart, and the on-device
/// integration_test files drive the two together on real hardware.

/// Tears the tree down inside the test body.
///
/// Forui's animated widgets (and drift's query streams) schedule timers that are
/// cancelled on dispose. Disposing here lets those fire before the test ends,
/// instead of tripping the framework's pending-timer assertion.
Future<void> disposeTree(WidgetTester tester) async {
  // Forui's FTappable schedules a 200ms press-feedback timer on tap, and drift's
  // query streams schedule one on cancel. Advance past both, then dispose, so they
  // fire inside the test instead of tripping the pending-timer assertion.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  late SakaDatabase db;

  setUp(() => db = SakaDatabase.memory());
  tearDown(() => db.close());

  Widget harness({
    required List<FieldEntity> fields,
    List<Override> extra = const [],
  }) =>
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => DateTime(2026, 3, 1)),
          fieldsProvider.overrideWith((ref) => Stream.value(fields)),
          ...extra,
        ],
        child: const SakaApp(home: FieldsScreen()),
      );

  FieldEntity field(String name, String ha) => FieldEntity(
        id: 'f-$name',
        name: name,
        area: SquareMetres.parseHectares(ha),
      );

  group('Field list', () {
    testWidgets('empty state invites the farmer to add a field', (tester) async {
      await tester.pumpWidget(harness(fields: const []));
      await tester.pump();
      expect(find.text('Add field'), findsWidgets);
      await disposeTree(tester);
    });

    testWidgets('lists fields with their area', (tester) async {
      await tester.pumpWidget(
        harness(fields: [field('Field 1', '2.5'), field('Field 2', '1')]),
      );
      await tester.pump();

      expect(find.text('Field 1'), findsOneWidget);
      expect(find.text('Field 2'), findsOneWidget);
      expect(find.textContaining('2.50 ha'), findsOneWidget);
      expect(find.textContaining('1.00 ha'), findsOneWidget);
      await disposeTree(tester);
    });
  });

  group('Field form validation', () {
    Future<void> openForm(WidgetTester tester) async {
      await tester.pumpWidget(harness(fields: const []));
      await tester.pump();
      await tester.tap(find.byIcon(FIcons.plus).last);
      await tester.pumpAndSettle();
    }

    testWidgets('rejects a blank name', (tester) async {
      await openForm(tester);
      await tester.enterText(
          find.byKey(const Key('field-area')), '2.5');
      await tester.tap(find.byKey(const Key('save-button')));
      await tester.pump();
      expect(find.text('Enter a name for this field'), findsOneWidget);
      await disposeTree(tester);
    });

    testWidgets('rejects a zero area (FR-002)', (tester) async {
      await openForm(tester);
      await tester.enterText(
          find.byKey(const Key('field-name')), 'Field 1');
      await tester.enterText(
          find.byKey(const Key('field-area')), '0');
      await tester.tap(find.byKey(const Key('save-button')));
      await tester.pump();
      expect(find.text('Area must be more than zero hectares'), findsOneWidget);
      await disposeTree(tester);
    });

    testWidgets('rejects non-numeric area rather than treating it as zero',
        (tester) async {
      await openForm(tester);
      await tester.enterText(
          find.byKey(const Key('field-name')), 'Field 1');
      await tester.enterText(
          find.byKey(const Key('field-area')), 'abc');
      await tester.tap(find.byKey(const Key('save-button')));
      await tester.pump();
      expect(find.text('Enter a number, like 2.5'), findsOneWidget);
      await disposeTree(tester);
    });

    testWidgets('rejects more precision than a centavo', (tester) async {
      // Silently truncating is the failure SC-009 forbids, so the farmer is told.
      await openForm(tester);
      await tester.enterText(
          find.byKey(const Key('field-name')), 'Field 1');
      await tester.enterText(
          find.byKey(const Key('field-area')), '2.50001');
      await tester.tap(find.byKey(const Key('save-button')));
      await tester.pump();
      expect(find.text('Use fewer decimal places'), findsOneWidget);
      await disposeTree(tester);
    });

    testWidgets('a valid field reaches the repository', (tester) async {
      await openForm(tester);
      await tester.enterText(
          find.byKey(const Key('field-name')), 'Field 1');
      await tester.enterText(
          find.byKey(const Key('field-area')), '2.5');
      await tester.tap(find.byKey(const Key('save-button')));
      await tester.pumpAndSettle();

      final saved = await db.select(db.fields).get();
      expect(saved.single.name, 'Field 1');
      expect(saved.single.areaSqm, 25000);
      await disposeTree(tester);
    });
  });

  group('Result view', () {
    /// quickstart Scenario 1 figures, harvested but not yet closed.
    CroppingResult scenarioOne(ResultState state) {
      final expenses = Centavos.fromPesos(23500);
      final revenue = Centavos.fromPesos(80000);
      final harvested = Grams.fromKg(5000);
      return CroppingResult(
        state: state,
        totalExpenses: expenses,
        revenue: revenue,
        netProfit: MoneyCalc.netProfit(revenue: revenue, expenses: expenses),
        harvested: harvested,
        tonsScaled2: 500,
        tonsPerHectareScaled2: 200,
        costPerKg:
            MoneyCalc.costPerKg(totalExpenses: expenses, harvested: harvested),
        remaining: Lot(Grams.fromKg(1000), WeightBasis.wet),
        breakdown: MoneyCalc.categoryBreakdown({
          ExpenseCategory.landPreparation: Centavos.fromPesos(12000),
          ExpenseCategory.seeds: Centavos.fromPesos(8000),
          ExpenseCategory.labor: Centavos.fromPesos(3500),
        }),
      );
    }

    /// The result list is taller than the default 800x600 test viewport, and a
    /// ListView only builds its visible children — so a short viewport would make
    /// the cost-per-kg row invisible to the finder rather than absent from the UI.
    void tallViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Widget resultHarness(CroppingResult result) => ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            croppingResultProvider('c1').overrideWith((ref) async => result),
          ],
          child: const SakaApp(home: CroppingResultView(croppingId: 'c1')),
        );

    testWidgets('shows every Scenario 1 figure, marked provisional',
        (tester) async {
      tallViewport(tester);
      await tester.pumpWidget(resultHarness(scenarioOne(ResultState.provisional)));
      await tester.pumpAndSettle();

      expect(find.textContaining('23,500.00'), findsWidgets);
      expect(find.textContaining('80,000.00'), findsWidgets);
      expect(find.textContaining('56,500.00'), findsWidgets);
      expect(find.textContaining('5.00'), findsWidgets);
      expect(find.textContaining('2.00'), findsWidgets);
      expect(find.textContaining('4.70'), findsWidgets);
      expect(find.textContaining('1,000.0 kg wet'), findsOneWidget);
      // FR-042a: harvested but open, so it must not read as final.
      expect(find.text('Provisional'), findsOneWidget);
      expect(find.text('Final'), findsNothing);
      await disposeTree(tester);
    });

    testWidgets('a closed cropping reads as final', (tester) async {
      tallViewport(tester);
      await tester.pumpWidget(resultHarness(scenarioOne(ResultState.isFinal)));
      await tester.pumpAndSettle();
      expect(find.text('Final'), findsOneWidget);
      expect(find.text('Provisional'), findsNothing);
      await disposeTree(tester);
    });

    testWidgets('before harvest, no revenue is shown and it is not a loss',
        (tester) async {
      tallViewport(tester);
      // FR-042: the absence of revenue must not be presented as a loss.
      await tester.pumpWidget(
        resultHarness(
          CroppingResult(
            state: ResultState.inProgress,
            totalExpenses: Centavos.fromPesos(12000),
            revenue: Centavos.zero,
            netProfit: Centavos.fromPesos(-12000),
            harvested: null,
            tonsScaled2: null,
            tonsPerHectareScaled2: null,
            costPerKg: null,
            remaining: null,
            breakdown: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('In progress'), findsOneWidget);
      expect(find.textContaining('12,000.00'), findsWidgets);
      expect(find.text('Loss'), findsNothing);
      expect(find.text('Total earned'), findsNothing);
      await disposeTree(tester);
    });

    testWidgets('a total crop failure shows cost per kg as not applicable',
        (tester) async {
      tallViewport(tester);
      // FR-041: never a division error.
      await tester.pumpWidget(
        resultHarness(
          CroppingResult(
            state: ResultState.provisional,
            totalExpenses: Centavos.fromPesos(8000),
            revenue: Centavos.zero,
            netProfit: Centavos.fromPesos(-8000),
            harvested: Grams.zero,
            tonsScaled2: 0,
            tonsPerHectareScaled2: 0,
            costPerKg: null,
            remaining: const Lot(Grams.zero, WeightBasis.wet),
            breakdown: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not applicable'), findsOneWidget);
      expect(find.text('Loss'), findsOneWidget);
      await disposeTree(tester);
    });
  });
}
