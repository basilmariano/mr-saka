import 'package:drift/drift.dart';

import '../../domain/model/calendar_date.dart';
import '../../platform/reminders/reminder_scheduler.dart';
import '../local/database.dart';
import '../local/repositories/application_repository.dart';
import '../local/repositories/cropping_repository.dart';
import '../local/repositories/field_repository.dart';
import 'reminder_sync.dart';

/// Rebuilds the device's pending reminders from the database.
///
/// research.md R6 — this exists because scheduled alarms are lost to more than
/// just time passing:
///   - Android drops exact alarms on reboot (the plugin's boot receiver handles
///     that, but only for notifications it still knows about)
///   - a force-stop, or an OEM battery manager clearing the app, loses them
///     entirely, which is common on exactly the low-end handsets this audience buys
///   - iOS caps pending notifications at 64, so a rolling window has to be topped
///     up as applications are completed and fall away
///
/// Run on app open and daily in the background. It is idempotent: ids are derived
/// from the application id and kind, so re-running replaces rather than stacks.
class ReminderReconciliation {
  ReminderReconciliation({
    required SakaDatabase database,
    required ReminderScheduler scheduler,
    required CroppingRepository croppings,
    required ApplicationRepository applications,
    required FieldRepository fields,
  })  : _db = database,
        _scheduler = scheduler,
        _croppings = croppings,
        _applications = applications,
        _fields = fields;

  final SakaDatabase _db;
  final ReminderScheduler _scheduler;
  final CroppingRepository _croppings;
  final ApplicationRepository _applications;
  final FieldRepository _fields;

  /// Recomputes and reinstalls every reminder. Returns how many are now pending.
  ///
  /// FR-019a: when the farmer has turned reminders off, everything is cancelled
  /// and nothing is scheduled — but the in-app upcoming and overdue lists are
  /// untouched, because those are a different surface and must keep working.
  Future<int> reconcile({
    required CalendarDate today,
    required bool remindersEnabled,
  }) async {
    if (!remindersEnabled) {
      await _scheduler.cancelAll();
      return 0;
    }

    final open = await _croppings.allOpen();
    final remindable = <RemindableCropping>[];

    for (final cropping in open) {
      final field = await _fields.byId(cropping.fieldId);
      if (field == null) continue;
      remindable.add(
        RemindableCropping(
          cropping: cropping,
          fieldName: field.name,
          area: field.area,
          applications: await _applications.forCropping(cropping.id),
        ),
      );
    }

    final reminders = ReminderPlanner.plan(
      croppings: remindable,
      today: today,
    );
    await _scheduler.replaceAll(reminders);
    return reminders.length;
  }

  /// Whether the farmer has reminders switched on. FR-019a. Defaults to on.
  Future<bool> remindersEnabled() async {
    final account = await _db.select(_db.accountState).getSingleOrNull();
    return account?.remindersEnabled ?? true;
  }

  Future<void> setRemindersEnabled(bool enabled) => _db
      .update(_db.accountState)
      .write(AccountStateCompanion(remindersEnabled: Value(enabled)));
}
