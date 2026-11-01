import '../../domain/model/calendar_date.dart';

/// Why a reminder is firing. FR-019 asks for both.
enum ReminderKind {
  /// Two days before the application is due, so there is time to buy fertilizer.
  lead,

  /// On the due date itself.
  dueDay,
}

/// One reminder the farmer should receive.
class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.applicationId,
    required this.croppingId,
    required this.kind,
    required this.fireDate,
    required this.fieldName,
    required this.product,
    required this.quantityBags,
  });

  /// Stable across reschedules: derived from the application id and kind, so
  /// replacing a schedule overwrites the same notification rather than stacking a
  /// second copy on top of it.
  final int id;

  final String applicationId;
  final String croppingId;
  final ReminderKind kind;

  /// Calendar date only. The time of day is applied by the scheduler
  /// ([ReminderScheduler.hourOfDay]) — a farmer should be reminded in the morning,
  /// not at whatever minute the record happened to be created.
  final CalendarDate fireDate;

  final String fieldName;
  final String product;

  /// Pre-formatted, e.g. "5.0". SC-004: the farmer reads off bags to buy without
  /// converting a per-hectare rate themselves, and that must hold in the
  /// notification too — not just on screen.
  final String quantityBags;

  /// Carried through the notification so tapping it can open the right cropping.
  String get payload => '$croppingId|$applicationId';

  /// Derives a stable notification id.
  ///
  /// Two reminders per application (lead and due-day) must not collide, so the
  /// kind is folded into the hash.
  static int idFor(String applicationId, ReminderKind kind) {
    // 31-bit positive: Android notification ids are ints and iOS wants a stable
    // identifier; negative values and overflow both cause silent drops.
    final hash = Object.hash(applicationId, kind.index);
    return hash & 0x3FFFFFFF;
  }
}

/// Scheduling local reminders. FR-019, FR-019a, FR-019b.
///
/// research.md R6: FR-019 requires delivery with the app closed and the device
/// offline, so the trigger must be local. Nothing server-side can satisfy it —
/// which is why this requirement, not the UI, drove the platform decisions.
///
/// The two platforms differ in ways that matter:
///   Android - exact alarms, re-registered on BOOT_COMPLETED by the plugin's own
///             receiver, at risk from OEM battery managers on exactly the low-end
///             handsets this audience buys.
///   iOS     - hard-capped at 64 pending notifications, so only a rolling window is
///             scheduled and topped up by the daily reconciliation.
///
/// Keeping both behind this interface means the scheduling LOGIC is unit-testable
/// against a fake, while delivery is verified on hardware (research.md R8).
abstract interface class ReminderScheduler {
  /// Days before the due date that the first reminder fires. FR-019.
  static const int leadDays = 2;

  /// iOS caps pending local notifications at 64. Staying well under it leaves room
  /// for both reminders per application and for a farmer with several active
  /// croppings; the daily reconciliation tops the window up as applications fall
  /// away.
  static const int maxPending = 48;

  /// Reminders fire at 7am local time — early enough to act on before a day's work,
  /// late enough not to wake anyone.
  static const int hourOfDay = 7;

  Future<void> initialize();

  /// Requests the permissions each platform needs. Returns false when the farmer
  /// declines — the app must still work, with the in-app overdue list carrying the
  /// weight (FR-018, FR-019a).
  Future<bool> requestPermissions();

  /// Replaces all scheduled reminders with [reminders], nearest first.
  ///
  /// Replace rather than add, because a changed planting date shifts every due date
  /// (spec edge case) and a stale alarm would fire on the old one.
  Future<void> replaceAll(List<ScheduledReminder> reminders);

  Future<void> cancelAll();

  Future<List<int>> pendingIds();

  /// Whether the OS will actually DELIVER what has been scheduled.
  ///
  /// Distinct from [requestPermissions], which reports what happened at the
  /// moment of asking. A farmer can allow notifications and revoke them later in
  /// system settings, and on Android 13+ a denied permission makes the post a
  /// silent no-op: the alarm still fires, the receiver still runs, and nothing
  /// appears. Nothing in the app would notice, so FR-019a's promise — that the
  /// farmer is told when delivery is blocked — needs this to be asked, not
  /// remembered.
  Future<bool> notificationsEnabled();
}

/// In-memory scheduler for tests.
class FakeReminderScheduler implements ReminderScheduler {
  final List<ScheduledReminder> scheduled = [];
  bool initialized = false;
  bool permissionsGranted = true;
  int replaceAllCalls = 0;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<bool> requestPermissions() async => permissionsGranted;

  @override
  Future<void> replaceAll(List<ScheduledReminder> reminders) async {
    replaceAllCalls++;
    scheduled
      ..clear()
      ..addAll(reminders.take(ReminderScheduler.maxPending));
  }

  @override
  Future<void> cancelAll() async => scheduled.clear();

  @override
  Future<List<int>> pendingIds() async => scheduled.map((r) => r.id).toList();

  @override
  Future<bool> notificationsEnabled() async => permissionsGranted;
}
