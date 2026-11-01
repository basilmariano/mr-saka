import '../../domain/model/calendar_date.dart';
import '../../domain/model/entities.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/square_metres.dart';
import '../../platform/reminders/reminder_scheduler.dart';

/// One cropping's schedule, with the context a reminder needs.
class RemindableCropping {
  const RemindableCropping({
    required this.cropping,
    required this.fieldName,
    required this.area,
    required this.applications,
  });

  final CroppingEntity cropping;
  final String fieldName;
  final SquareMetres area;
  final List<ScheduledApplicationEntity> applications;
}

/// Turns croppings into the reminders that should be pending. FR-019, FR-019b.
///
/// Pure: no database, no plugin, no clock of its own. That is what makes the rules
/// below testable without a device — delivery is verified on hardware, but WHICH
/// reminders exist is decided here and checked in CI (research.md R8).
abstract final class ReminderPlanner {
  /// Builds the reminder set for [croppings], nearest first.
  ///
  /// FR-019: two reminders per pending application — [ReminderScheduler.leadDays]
  /// before the due date, and on the due date itself.
  ///
  /// FR-019b suppresses a reminder when:
  ///   - the application is already done or skipped — the farmer has dealt with it
  ///   - the cropping is harvested or closed — the season is over, and the spec's
  ///     "Pending steps at harvest time" edge case says pending steps stop being
  ///     shown as due
  ///
  /// A reminder whose date has already passed is dropped rather than scheduled: a
  /// notification that fires immediately for something overdue is noise, and the
  /// in-app overdue list (FR-018) is the right surface for that.
  static List<ScheduledReminder> plan({
    required List<RemindableCropping> croppings,
    required CalendarDate today,
    int limit = ReminderScheduler.maxPending,
  }) {
    final reminders = <ScheduledReminder>[];

    for (final entry in croppings) {
      // FR-019b: the season is over; nothing more is due.
      if (!_isGrowing(entry.cropping.status)) continue;

      for (final application in entry.applications) {
        // FR-019b: already dealt with.
        if (!application.isPending) continue;

        final due = application.dueDate(entry.cropping.plantingDate);
        final lead = due.addDays(-ReminderScheduler.leadDays);
        final bags = application
            .recommendedQuantity(entry.area)
            .formatBags();

        for (final (kind, date) in [
          (ReminderKind.lead, lead),
          (ReminderKind.dueDay, due),
        ]) {
          if (date.isBefore(today)) continue;
          reminders.add(
            ScheduledReminder(
              id: ScheduledReminder.idFor(application.id, kind),
              applicationId: application.id,
              croppingId: entry.cropping.id,
              kind: kind,
              fireDate: date,
              fieldName: entry.fieldName,
              product: application.recommendedProduct,
              quantityBags: bags,
            ),
          );
        }
      }
    }

    // Nearest first, so the iOS rolling window keeps what matters soonest. Without
    // this, truncating to the cap would drop reminders at random and a farmer
    // would silently stop being reminded about the next application.
    reminders.sort((a, b) => a.fireDate.compareTo(b.fireDate));
    return reminders.take(limit).toList();
  }

  /// Only a cropping still in the ground generates reminders.
  static bool _isGrowing(CroppingStatus status) =>
      status == CroppingStatus.planted || status == CroppingStatus.growing;
}
