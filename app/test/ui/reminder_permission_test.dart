import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saka/data/local/database.dart';
import 'package:saka/platform/reminders/reminder_scheduler.dart';
import 'package:saka/ui/account/settings_screen.dart';
import 'package:saka/ui/common/app.dart';
import 'package:saka/ui/common/providers.dart';

/// FR-019a: the farmer must be told when the phone is blocking delivery.
///
/// This exists because of what a device run showed: with the notification
/// permission denied on Android 13+, the alarm is still armed, the receiver still
/// fires, and NotificationManager drops the post silently — no error, no retry, no
/// trace. The reminders switch read ON throughout. Nothing in the app could tell
/// the difference between "delivered" and "discarded", so the warning is the only
/// signal the farmer gets, and it has to be driven by the live permission rather
/// than by what the farmer answered when they were last asked.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SakaDatabase db;
  late FakeReminderScheduler scheduler;

  setUp(() {
    db = SakaDatabase.memory();
    scheduler = FakeReminderScheduler();
  });
  tearDown(() => db.close());

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        reminderSchedulerProvider.overrideWithValue(scheduler),
        clockProvider.overrideWithValue(() => DateTime(2026, 3, 1)),
      ],
      child: const SakaApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('warns when the phone is blocking notifications', (tester) async {
    scheduler.permissionsGranted = false;
    await pumpSettings(tester);

    expect(find.byKey(const Key('reminders-blocked')), findsOneWidget);
  });

  testWidgets('stays quiet when notifications are permitted', (tester) async {
    scheduler.permissionsGranted = true;
    await pumpSettings(tester);

    expect(find.byKey(const Key('reminders-blocked')), findsNothing);
  });

  testWidgets('no warning when the farmer turned reminders off themselves',
      (tester) async {
    // Nothing is being blocked if nothing was meant to be delivered; warning here
    // would be noise about a state the farmer chose.
    scheduler.permissionsGranted = false;
    await pumpSettings(tester);
    expect(find.byKey(const Key('reminders-blocked')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reminders-switch')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reminders-blocked')), findsNothing);
  });

  testWidgets('the warning fits a phone screen', (tester) async {
    // layout_phone_test.dart cannot reach this: it builds SettingsScreen with the
    // default fake scheduler, which reports permissions granted, so the alert is
    // never rendered there. The string is long and phase 2 translates it into a
    // language with longer words, which is exactly the shape that has broken forui
    // layouts before.
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final captured = <FlutterErrorDetails>[];
    final original = FlutterError.onError;
    FlutterError.onError = captured.add;

    scheduler.permissionsGranted = false;
    await pumpSettings(tester);

    FlutterError.onError = original;
    final overflows = captured
        .where((d) => d.exception.toString().contains('overflowed'))
        .map((d) => d.exception.toString())
        .toList();
    expect(overflows, isEmpty, reason: overflows.join('\n'));
    expect(find.byKey(const Key('reminders-blocked')), findsOneWidget);
  });

  testWidgets('a revoked permission is noticed, not remembered', (tester) async {
    // The farmer allowed notifications once and revoked them in system settings
    // later. Caching the answer from the prompt would leave the app confident and
    // silent while every reminder is discarded.
    scheduler.permissionsGranted = true;
    await pumpSettings(tester);
    expect(find.byKey(const Key('reminders-blocked')), findsNothing);

    scheduler.permissionsGranted = false;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    container.invalidate(notificationsPermittedProvider);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reminders-blocked')), findsOneWidget);
  });
}
