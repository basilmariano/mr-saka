import 'package:flutter_test/flutter_test.dart';
import 'package:saka/data/sync/reminder_sync.dart';
import 'package:saka/domain/model/calendar_date.dart';
import 'package:saka/domain/model/entities.dart';
import 'package:saka/domain/model/enums.dart';
import 'package:saka/domain/model/grams.dart';
import 'package:saka/domain/model/square_metres.dart';
import 'package:saka/platform/reminders/reminder_scheduler.dart';

/// FR-019, FR-019a, FR-019b and the iOS rolling window (research.md R6).
///
/// These cover WHICH reminders should exist. Whether they actually fire with the
/// app closed and the device offline can only be proven on hardware — quickstart
/// Scenario 5 — and these tests do not pretend otherwise.
void main() {
  const today = CalendarDate(2026, 3, 1);
  final area = SquareMetres.parseHectares('2.5');

  ScheduledApplicationEntity application(
    String id,
    int days, {
    ApplicationState state = ApplicationState.pending,
    int ratePerHectareKg = 100,
  }) =>
      ScheduledApplicationEntity(
        id: id,
        croppingId: 'c1',
        daysAfterPlanting: days,
        growthStage: 'Basal',
        recommendedProduct: 'Urea 46-0-0',
        ratePerHectare: Grams.fromKg(ratePerHectareKg),
        sortOrder: days,
        state: state,
      );

  RemindableCropping cropping({
    CroppingStatus status = CroppingStatus.growing,
    required List<ScheduledApplicationEntity> applications,
    String id = 'c1',
    CalendarDate plantingDate = today,
  }) =>
      RemindableCropping(
        cropping: CroppingEntity(
          id: id,
          fieldId: 'f1',
          crop: Crop.rice,
          varietyId: 'v1',
          plantingMethod: PlantingMethod.transplanted,
          growingSeason: GrowingSeason.wet,
          plantingDate: plantingDate,
          status: status,
        ),
        fieldName: 'Field 1',
        area: area,
        applications: applications,
      );

  group('FR-019 — two reminders per pending application', () {
    test('fires 2 days before the due date and again on the due date', () {
      // A step 14 days after a 1 March planting is due 15 March.
      final reminders = ReminderPlanner.plan(
        croppings: [cropping(applications: [application('a1', 14)])],
        today: today,
      );

      expect(reminders, hasLength(2));
      expect(reminders[0].kind, ReminderKind.lead);
      expect(reminders[0].fireDate, const CalendarDate(2026, 3, 13));
      expect(reminders[1].kind, ReminderKind.dueDay);
      expect(reminders[1].fireDate, const CalendarDate(2026, 3, 15));
    });

    test('carries the bag count the farmer needs to buy', () {
      // SC-004 must hold in the notification too, not just on screen:
      // 100 kg/ha on 2.5 ha is 5.0 bags.
      final reminders = ReminderPlanner.plan(
        croppings: [cropping(applications: [application('a1', 14)])],
        today: today,
      );
      expect(reminders.first.quantityBags, '5.0');
      expect(reminders.first.product, 'Urea 46-0-0');
      expect(reminders.first.fieldName, 'Field 1');
    });

    test('ids are stable and distinct per kind, so rescheduling replaces', () {
      final first = ReminderPlanner.plan(
        croppings: [cropping(applications: [application('a1', 14)])],
        today: today,
      );
      final second = ReminderPlanner.plan(
        croppings: [cropping(applications: [application('a1', 14)])],
        today: today,
      );

      expect(first.map((r) => r.id).toList(), second.map((r) => r.id).toList());
      expect(first[0].id, isNot(first[1].id));
      expect(first.every((r) => r.id >= 0), isTrue);
    });

    test('a reminder whose date has passed is not scheduled', () {
      // Firing immediately for something already overdue is noise; the in-app
      // overdue list (FR-018) is the right surface for that.
      final reminders = ReminderPlanner.plan(
        croppings: [cropping(applications: [application('a1', 0)])],
        today: const CalendarDate(2026, 3, 10),
      );
      expect(reminders, isEmpty);
    });

    test('the due-day reminder survives once the lead date has passed', () {
      final reminders = ReminderPlanner.plan(
        croppings: [cropping(applications: [application('a1', 14)])],
        today: const CalendarDate(2026, 3, 14),
      );
      expect(reminders, hasLength(1));
      expect(reminders.single.kind, ReminderKind.dueDay);
    });
  });

  group('FR-019b — suppression', () {
    test('no reminder for an application already done', () {
      final reminders = ReminderPlanner.plan(
        croppings: [
          cropping(
            applications: [application('a1', 14, state: ApplicationState.done)],
          ),
        ],
        today: today,
      );
      expect(reminders, isEmpty);
    });

    test('no reminder for an application skipped', () {
      final reminders = ReminderPlanner.plan(
        croppings: [
          cropping(
            applications: [
              application('a1', 14, state: ApplicationState.skipped),
            ],
          ),
        ],
        today: today,
      );
      expect(reminders, isEmpty);
    });

    for (final status in [CroppingStatus.harvested, CroppingStatus.closed]) {
      test('no reminder once the cropping is ${status.name}', () {
        // spec edge case "Pending steps at harvest time": pending steps stop
        // being shown as due once the crop is off the field.
        final reminders = ReminderPlanner.plan(
          croppings: [
            cropping(status: status, applications: [application('a1', 14)]),
          ],
          today: today,
        );
        expect(reminders, isEmpty);
      });
    }

    test('a planted cropping still reminds', () {
      final reminders = ReminderPlanner.plan(
        croppings: [
          cropping(
            status: CroppingStatus.planted,
            applications: [application('a1', 14)],
          ),
        ],
        today: today,
      );
      expect(reminders, hasLength(2));
    });
  });

  group('iOS rolling window (research.md R6)', () {
    test('never exceeds the pending cap', () {
      // iOS hard-caps pending local notifications at 64. Scheduling a whole
      // season across several croppings would blow past it and the OS would
      // silently drop the overflow.
      final many = [
        for (var c = 0; c < 10; c++)
          cropping(
            id: 'c$c',
            applications: [
              for (var a = 0; a < 8; a++) application('c$c-a$a', 10 + a * 7),
            ],
          ),
      ];

      final reminders = ReminderPlanner.plan(croppings: many, today: today);

      expect(reminders.length, ReminderScheduler.maxPending);
      expect(ReminderScheduler.maxPending, lessThan(64));
    });

    test('keeps the nearest reminders when truncating', () {
      // Truncating arbitrarily would silently stop reminding about the NEXT
      // application while keeping one months away.
      final many = [
        for (var c = 0; c < 10; c++)
          cropping(
            id: 'c$c',
            applications: [
              for (var a = 0; a < 8; a++) application('c$c-a$a', 10 + a * 7),
            ],
          ),
      ];

      final reminders = ReminderPlanner.plan(croppings: many, today: today);
      final dates = reminders.map((r) => r.fireDate).toList();

      expect(dates, orderedEquals([...dates]..sort()));
      // The soonest possible reminder is 10 days after planting, less the lead.
      expect(dates.first, const CalendarDate(2026, 3, 9));
    });
  });

  group('FakeReminderScheduler', () {
    test('replaceAll truncates to the cap', () async {
      final scheduler = FakeReminderScheduler();
      await scheduler.replaceAll([
        for (var i = 0; i < 100; i++)
          ScheduledReminder(
            id: i,
            applicationId: 'a$i',
            croppingId: 'c1',
            kind: ReminderKind.dueDay,
            fireDate: today,
            fieldName: 'Field 1',
            product: 'Urea',
            quantityBags: '5.0',
          ),
      ]);
      expect(scheduler.scheduled, hasLength(ReminderScheduler.maxPending));
    });

    test('replaceAll replaces rather than appends', () async {
      final scheduler = FakeReminderScheduler();
      const one = ScheduledReminder(
        id: 1,
        applicationId: 'a1',
        croppingId: 'c1',
        kind: ReminderKind.dueDay,
        fireDate: today,
        fieldName: 'Field 1',
        product: 'Urea',
        quantityBags: '5.0',
      );
      await scheduler.replaceAll([one]);
      await scheduler.replaceAll([one]);
      // A changed planting date shifts every due date; appending would leave a
      // stale alarm firing on the old one.
      expect(scheduler.scheduled, hasLength(1));
      expect(scheduler.replaceAllCalls, 2);
    });
  });
}
