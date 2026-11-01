import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/reference/reference_seeder.dart';
import 'data/remote/api_client.dart';
import 'data/remote/app_config.dart';
import 'data/remote/auth_session.dart';
import 'data/remote/cognito_auth_session.dart';
import 'data/sync/background_tasks.dart';
import 'platform/reminders/local_notification_scheduler.dart';
import 'platform/reminders/reminder_scheduler.dart';
import 'ui/common/app.dart';
import 'ui/common/providers.dart';
import 'ui/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final scheduler = (Platform.isAndroid || Platform.isIOS)
      ? LocalNotificationScheduler()
      // Desktop and test hosts get the in-memory scheduler so the app still runs.
      : FakeReminderScheduler();
  await scheduler.initialize();

  // Which backend, if any, this build talks to. Null is the fresh-clone case and
  // the deliberate guest-only case; it is not an error (see AppConfig).
  final config = AppConfig.fromEnvironment();
  final auth = config == null
      ? LocalAuthSessionProvider()
      : CognitoAuthSessionProvider(config: config);

  final container = ProviderContainer(
    overrides: [
      reminderSchedulerProvider.overrideWithValue(scheduler),
      appConfigProvider.overrideWithValue(config),
      authSessionProvider.overrideWithValue(auth),
      if (config != null)
        apiClientProvider.overrideWithValue(_apiClient(config, auth)),
    ],
  );

  // Without this the variety list is empty and no cropping can generate a
  // schedule, because there is no template to generate one from (FR-026e).
  await ReferenceSeeder(container.read(databaseProvider)).seedIfNeeded();

  final today = container.read(todayProvider);

  // FR-011a, FR-011b: advance planted -> growing on app open. A date comparison
  // on the device, so a cropping advances on time even with no signal.
  await container.read(croppingRepositoryProvider).refreshStatuses(today);

  // research.md R6: alarms are lost to reboot, force-stop, and OEM battery
  // managers. Reinstalling on every launch is the cheap half of the mitigation;
  // the daily background task is the other half.
  final reconciliation = container.read(reminderReconciliationProvider);
  await reconciliation.reconcile(
    today: today,
    remindersEnabled: await reconciliation.remindersEnabled(),
  );

  // Reinstall reminders on every resume too, not just launch: alarms are lost
  // to reboot, force-stop and OEM battery managers, and a farmer who reopens
  // the app should not have to notice (see ReminderLifecycleObserver).
  ReminderLifecycleObserver(
    reconciliation: reconciliation,
    today: () => container.read(todayProvider),
  ).start();

  runApp(
    UncontrolledProviderScope(
      container: container,
      // US3: the home screen is the entry point — what needs attention, first.
      child: const SakaApp(home: HomeScreen()),
    ),
  );
}

/// The API client, with the bearer token attached per request.
///
/// Per request rather than once at construction, because an access token lasts an
/// hour and a farmer's session lasts a year (FR-065). [AuthSessionProvider.accessToken]
/// refreshes when it can and returns null when it cannot — offline, say — and a
/// request that goes out unauthenticated is refused by the API and retried later,
/// which is exactly the behaviour the outbox is built for.
ApiClient _apiClient(AppConfig config, AuthSessionProvider auth) {
  final dio = Dio(BaseOptions(baseUrl: config.apiBaseUrl));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await auth.accessToken();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
    ),
  );
  return ApiClient(dio: dio);
}
