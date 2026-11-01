import 'package:flutter/widgets.dart';

import '../../domain/model/calendar_date.dart';
import 'reminder_reconciliation.dart';

/// Keeps reminders current while the app is in use.
///
/// ## Why there is no background task here
///
/// research.md R6 originally called for a daily WorkManager job. That is not
/// possible on this Flutter version: no published `workmanager` release works
/// with Flutter 3.35 — 0.9.3+ requires Flutter 3.38, 0.9.2 ships a federated
/// split whose iOS package does not implement its own platform interface, and
/// 0.5.2 uses the v1 plugin embedding that Flutter removed. The dependency was
/// dropped rather than pinning Flutter to a broken middle.
///
/// What that actually costs is small, because the two things R6 worried about
/// are covered elsewhere:
///
///   - **Reboot.** `flutter_local_notifications` re-registers its own scheduled
///     notifications through `ScheduledNotificationBootReceiver`, declared in
///     AndroidManifest.xml. That never depended on WorkManager.
///   - **Alarms lost to a force-stop or an OEM battery manager.** These are
///     reinstalled when the app next runs — on launch (main.dart) and now on
///     every resume (below). A farmer who opens the app at all is covered.
///
/// What is genuinely lost: topping up the iOS 48-reminder rolling window for a
/// farmer who does not open the app for weeks. Reconciling on resume covers far
/// more real usage than a background job the OS may decline to run anyway —
/// which, on the low-end handsets this audience buys, R6 says is likely.
class ReminderLifecycleObserver with WidgetsBindingObserver {
  ReminderLifecycleObserver({
    required ReminderReconciliation reconciliation,
    required CalendarDate Function() today,
  })  : _reconciliation = reconciliation,
        _today = today;

  final ReminderReconciliation _reconciliation;
  final CalendarDate Function() _today;

  void start() => WidgetsBinding.instance.addObserver(this);
  void stop() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Fire and forget: a failure here must never block the app. Reminders are a
    // feature, not a precondition — the in-app overdue list still works (FR-018).
    _reconcile();
  }

  Future<void> _reconcile() async {
    try {
      await _reconciliation.reconcile(
        today: _today(),
        remindersEnabled: await _reconciliation.remindersEnabled(),
      );
    } catch (_) {
      // Left to the next resume.
    }
  }
}
