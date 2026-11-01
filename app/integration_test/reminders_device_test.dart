import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:saka/domain/model/calendar_date.dart';
import 'package:saka/platform/reminders/local_notification_scheduler.dart';
import 'package:saka/platform/reminders/reminder_scheduler.dart';

/// FR-019 on real hardware — the scheduling MECHANISM.
///
/// Everything else about reminders is unit-tested against a fake: which reminders
/// should exist, the suppression rules, the iOS rolling window. None of that
/// touches the platform. This file is the part that cannot be faked — that the OS
/// accepts an exact alarm, creates the channel and holds the notification pending.
///
/// WHAT THIS DOES NOT PROVE: quickstart Scenario 5's real risk. An emulator has no
/// OEM battery manager, so it cannot show whether a Xiaomi or Oppo handset silently
/// drops the alarm after a force-stop. research.md R6 flags that as the open
/// question and it needs a physical phone of the kind the target farmers buy.
///
/// RUNNING ON iOS NEEDS ONE TAP. The setUp below asks for authorisation on iOS, and
/// `flutter test` reinstalls the app each run, so the system prompt appears every
/// time and the run sits on it until someone taps Allow. That is not a hang — the
/// six cases pass once it is dismissed. Android needs no tap.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late LocalNotificationScheduler scheduler;

  setUp(() async {
    scheduler = LocalNotificationScheduler();
    await scheduler.initialize();
    // The two platforms genuinely differ here, and the difference decides whether
    // this file may ask for permission at all:
    //
    //   Android - AlarmManager arms the alarm whether or not POST_NOTIFICATIONS is
    //             granted; the permission only gates DISPLAY. Asking is also
    //             actively harmful, because `flutter test` reinstalls the APK each
    //             run, which revokes the grant, so the request raises a system
    //             dialog nobody is there to tap and the run hangs to its timeout.
    //   iOS     - UNUserNotificationCenter registers nothing while unauthorised, so
    //             without asking there is no pending request to assert on and every
    //             case below fails for a reason that has nothing to do with the
    //             scheduling logic under test.
    //
    // Delivery itself is covered by test/ui/reminder_permission_test.dart and by
    // the device evidence recorded in research.md R6.
    if (Platform.isIOS) await scheduler.requestPermissions();
  });

  tearDown(() => scheduler.cancelAll());

  ScheduledReminder reminder(String id, ReminderKind kind, CalendarDate date) =>
      ScheduledReminder(
        id: ScheduledReminder.idFor(id, kind),
        applicationId: id,
        croppingId: 'c1',
        kind: kind,
        fireDate: date,
        fieldName: 'Field 1',
        product: 'Urea 46-0-0',
        quantityBags: '5.0',
      );

  /// Far enough ahead that the scheduler will not discard it as past.
  CalendarDate soon([int days = 3]) =>
      CalendarDate.fromDateTime(DateTime.now().add(Duration(days: days)));

  testWidgets('the OS accepts a scheduled reminder and holds it pending',
      (tester) async {
    await scheduler.replaceAll([reminder('a1', ReminderKind.dueDay, soon())]);

    final pending = await scheduler.pendingIds();
    expect(
      pending,
      contains(ScheduledReminder.idFor('a1', ReminderKind.dueDay)),
      reason: 'the platform did not hold the alarm — FR-019 cannot work',
    );
  });

  testWidgets('both reminders for one application are held separately',
      (tester) async {
    // FR-019 asks for two per application. Ids are derived from the application
    // id and kind, so a collision would silently drop one of them.
    await scheduler.replaceAll([
      reminder('a1', ReminderKind.lead, soon(1)),
      reminder('a1', ReminderKind.dueDay, soon(3)),
    ]);

    final pending = await scheduler.pendingIds();
    expect(pending, hasLength(2));
    expect(pending.toSet(), hasLength(2), reason: 'ids collided');
  });

  testWidgets('replaceAll replaces rather than accumulating', (tester) async {
    // A changed planting date shifts every due date; appending would leave a
    // stale alarm firing on the old one.
    final one = [reminder('a1', ReminderKind.dueDay, soon())];
    await scheduler.replaceAll(one);
    await scheduler.replaceAll(one);
    await scheduler.replaceAll(one);

    expect(await scheduler.pendingIds(), hasLength(1));
  });

  testWidgets('a reminder already in the past is not scheduled', (tester) async {
    // Firing immediately for something overdue is noise; the in-app overdue list
    // (FR-018) is the right surface for that.
    await scheduler.replaceAll([
      reminder('a1', ReminderKind.dueDay, const CalendarDate(2020, 1, 1)),
    ]);
    expect(await scheduler.pendingIds(), isEmpty);
  });

  testWidgets('cancelAll clears everything', (tester) async {
    // FR-019a: switching reminders off must leave nothing pending.
    await scheduler.replaceAll([
      reminder('a1', ReminderKind.lead, soon(1)),
      reminder('a2', ReminderKind.dueDay, soon(2)),
    ]);
    expect(await scheduler.pendingIds(), isNotEmpty);

    await scheduler.cancelAll();
    expect(await scheduler.pendingIds(), isEmpty);
  });

  testWidgets('the pending cap is respected', (tester) async {
    // iOS hard-caps pending local notifications at 64 and silently drops the
    // overflow. Android has no such cap, but the same window keeps both
    // platforms on one code path.
    await scheduler.replaceAll([
      for (var i = 0; i < 80; i++)
        reminder('a$i', ReminderKind.dueDay, soon(i + 1)),
    ]);

    final pending = await scheduler.pendingIds();
    expect(pending.length, lessThanOrEqualTo(ReminderScheduler.maxPending));
    expect(pending, isNotEmpty);
  });
}
