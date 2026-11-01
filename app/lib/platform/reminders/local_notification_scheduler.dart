import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_scheduler.dart';

/// Real local notifications. FR-019, research.md R6.
///
/// One implementation covers both platforms: `flutter_local_notifications` already
/// provides Android exact alarms (`AndroidScheduleMode.exactAllowWhileIdle`, which
/// maps to `AlarmManager.setExactAndAllowWhileIdle`) and boot re-registration via
/// the `ScheduledNotificationBootReceiver` declared in AndroidManifest.xml. A
/// separate alarm-manager package would add a second registry to keep in sync with
/// [replaceAll] for no extra capability.
///
/// The platform differences that DO matter are handled explicitly below:
/// permissions, exact-alarm availability, and the iOS pending cap.
class LocalNotificationScheduler implements ReminderScheduler {
  LocalNotificationScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    this.localTimeZone = 'Asia/Manila',
    this.labels = const ReminderLabels(),
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// The audience is single-timezone. `tz.local` defaults to UTC until it is set,
  /// which would shift every Philippine reminder by eight hours — a 7am reminder
  /// arriving at 3pm, after the work it was meant to prompt.
  final String localTimeZone;

  final ReminderLabels labels;

  static const _channelId = 'fertilizer_reminders';

  bool _exactAlarmsAvailable = true;

  @override
  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(localTimeZone));

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // All three default to true and would prompt during initialize. Asking is
        // deferred to requestPermissions() so the farmer sees the prompt in
        // context, not on first launch before they know what the app does.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // Scheduling an exact alarm when the permission is absent throws natively,
      // so this is checked rather than assumed.
      _exactAlarmsAvailable =
          await android?.canScheduleExactNotifications() ?? false;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final notifications = await android?.requestNotificationsPermission();
      final exact = await android?.requestExactAlarmsPermission();
      _exactAlarmsAvailable = exact ?? _exactAlarmsAvailable;
      return notifications ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      // These all default to false, so they must be asked for explicitly.
      return await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  @override
  Future<void> replaceAll(List<ScheduledReminder> reminders) async {
    await cancelAll();

    // iOS silently drops anything past 64 pending notifications. Taking the
    // nearest-first list the planner produced keeps the next application covered.
    for (final reminder in reminders.take(ReminderScheduler.maxPending)) {
      final when = tz.TZDateTime(
        tz.local,
        reminder.fireDate.year,
        reminder.fireDate.month,
        reminder.fireDate.day,
        ReminderScheduler.hourOfDay,
      );
      // A reminder in the past would fire immediately, which is noise.
      if (when.isBefore(tz.TZDateTime.now(tz.local))) continue;

      await _plugin.zonedSchedule(
        reminder.id,
        labels.title(reminder),
        labels.body(reminder),
        when,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            labels.channelName,
            channelDescription: labels.channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            // Groups a cropping's reminders together in Notification Centre.
            threadIdentifier: reminder.croppingId,
          ),
        ),
        androidScheduleMode: _exactAlarmsAvailable
            ? AndroidScheduleMode.exactAllowWhileIdle
            // Falling back keeps reminders working, a little less precisely,
            // rather than throwing and delivering nothing at all.
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: reminder.payload,
      );
    }
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<bool> notificationsEnabled() async {
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final options = await ios?.checkPermissions();
      // Provisional counts: a quiet notification still reaches Notification
      // Centre, which is where a farmer checking the morning's work will look.
      return (options?.isEnabled ?? false) ||
          (options?.isProvisionalEnabled ?? false);
    }
    return false;
  }

  @override
  Future<List<int>> pendingIds() async {
    final pending = await _plugin.pendingNotificationRequests();
    return pending.map((request) => request.id).toList();
  }
}

/// Notification copy.
///
/// Held here rather than inlined so FR-056 still holds: the strings are supplied
/// from the localised resources at the call site, and the phase-2 local language
/// needs no change to this class.
class ReminderLabels {
  const ReminderLabels({
    this.channelName = 'Fertilizer reminders',
    this.channelDescription = 'Reminders before each fertilizer application is due',
    this.leadTitle = 'Fertilizer due in 2 days',
    this.dueTitle = 'Fertilizer due today',
  });

  final String channelName;
  final String channelDescription;
  final String leadTitle;
  final String dueTitle;

  String title(ScheduledReminder reminder) =>
      reminder.kind == ReminderKind.lead ? leadTitle : dueTitle;

  /// SC-004 applies here too: the farmer should see how many bags to buy without
  /// opening the app.
  String body(ScheduledReminder reminder) =>
      '${reminder.fieldName}: ${reminder.quantityBags} bags of ${reminder.product}';
}
