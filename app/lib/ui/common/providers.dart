import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database.dart';
import '../../data/local/write_through.dart';
import '../../data/local/repositories/account_repository.dart';
import '../../data/local/repositories/application_repository.dart';
import '../../data/local/repositories/cropping_repository.dart';
import '../../data/local/repositories/expense_repository.dart';
import '../../data/local/repositories/field_repository.dart';
import '../../data/local/repositories/comparison_repository.dart';
import '../../data/local/repositories/home_repository.dart';
import '../../data/local/repositories/template_repository.dart';
import '../../data/local/repositories/harvest_repository.dart';
import '../../data/local/repositories/result_repository.dart';
import '../../data/local/repositories/sale_repository.dart';
import '../../domain/model/calendar_date.dart';
import '../../domain/model/entities.dart';
import '../../domain/model/reference.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/app_config.dart';
import '../../data/remote/auth_session.dart';
import '../../data/reference/template_lookup.dart';
import '../../data/sync/reminder_reconciliation.dart';
import '../../data/sync/sync_worker.dart';
import '../../platform/reminders/reminder_scheduler.dart';

/// The device database. Overridden in tests with an in-memory instance.
final databaseProvider = Provider<SakaDatabase>((ref) {
  final db = SakaDatabase(openDatabase());
  ref.onDispose(db.close);
  return db;
});

/// Today, as a calendar date.
///
/// A provider rather than a bare `DateTime.now()` so the PLANTED -> GROWING
/// transition (FR-011a) can be exercised at any date in tests without waiting ten
/// days for one to pass.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final todayProvider = Provider<CalendarDate>(
  (ref) => CalendarDate.fromDateTime(ref.watch(clockProvider)()),
);

/// Overridden per platform at startup, and with a fake in tests (research.md R6, R8).
final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => FakeReminderScheduler(),
);

final fieldRepositoryProvider =
    Provider((ref) => FieldRepository(ref.watch(databaseProvider)));
final templateLookupProvider =
    Provider((ref) => TemplateLookup(ref.watch(databaseProvider)));

final applicationRepositoryProvider = Provider(
  (ref) => ApplicationRepository(
    ref.watch(databaseProvider),
    expenses: ref.watch(expenseRepositoryProvider),
  ),
);

/// Starting a cropping also generates its fertilizer schedule (FR-014), so the
/// repository is given both collaborators here rather than at each call site.
final croppingRepositoryProvider = Provider(
  (ref) => CroppingRepository(
    ref.watch(databaseProvider),
    applications: ref.watch(applicationRepositoryProvider),
    templates: ref.watch(templateLookupProvider),
  ),
);
final expenseRepositoryProvider =
    Provider((ref) => ExpenseRepository(ref.watch(databaseProvider)));
final harvestRepositoryProvider =
    Provider((ref) => HarvestRepository(ref.watch(databaseProvider)));
final saleRepositoryProvider =
    Provider((ref) => SaleRepository(ref.watch(databaseProvider)));

final resultRepositoryProvider = Provider(
  (ref) => ResultRepository(
    expenses: ref.watch(expenseRepositoryProvider),
    harvests: ref.watch(harvestRepositoryProvider),
    sales: ref.watch(saleRepositoryProvider),
  ),
);

/// Active (non-archived) fields.
final fieldsProvider = StreamProvider<List<FieldEntity>>(
  (ref) => ref.watch(fieldRepositoryProvider).watchActive(),
);

final fieldByIdProvider = FutureProvider.family<FieldEntity?, String>(
  (ref, id) => ref.watch(fieldRepositoryProvider).byId(id),
);

/// Croppings for a field, newest first.
final croppingsForFieldProvider =
    FutureProvider.family<List<CroppingEntity>, String>(
  (ref, fieldId) => ref.watch(croppingRepositoryProvider).forField(fieldId),
);

final croppingByIdProvider = FutureProvider.family<CroppingEntity?, String>(
  (ref, id) => ref.watch(croppingRepositoryProvider).byId(id),
);

/// Expenses for a cropping, so totals refresh as the farmer logs.
final expensesForCroppingProvider =
    StreamProvider.family<List<ExpenseEntity>, String>(
  (ref, croppingId) =>
      ref.watch(expenseRepositoryProvider).watchForCropping(croppingId),
);

/// The assembled result for a cropping (FR-039 to FR-042b).
final croppingResultProvider =
    FutureProvider.family<CroppingResult?, String>((ref, croppingId) async {
  final cropping = await ref.watch(croppingByIdProvider(croppingId).future);
  if (cropping == null) return null;
  final field = await ref.watch(fieldByIdProvider(cropping.fieldId).future);
  if (field == null) return null;
  return ref
      .watch(resultRepositoryProvider)
      .forCropping(cropping: cropping, area: field.area);
});

/// Harvest for a cropping, if recorded.
final harvestForCroppingProvider =
    FutureProvider.family<HarvestEntity?, String>(
  (ref, croppingId) =>
      ref.watch(harvestRepositoryProvider).forCropping(croppingId),
);

final salesForCroppingProvider =
    FutureProvider.family<List<SaleEntity>, String>(
  (ref, croppingId) => ref.watch(saleRepositoryProvider).forCropping(croppingId),
);

// ---------------------------------------------------------------- durability

/// Which backend this build talks to, or null when none is configured.
///
/// `main.dart` overrides this from build-time defines. Null is a supported state, not a
/// failure: the app then runs guest-only, and [signInAvailableProvider] is what
/// the UI checks so it never offers an account it cannot actually create.
final appConfigProvider = Provider<AppConfig?>((ref) => null);

/// Whether this build can really sign a farmer in.
///
/// False means the fallback stub is in place. The sign-in screen must not offer
/// its buttons then: the stub would report success, and a farmer would believe
/// their records were backed up while nothing had left the phone.
final signInAvailableProvider =
    Provider<bool>((ref) => ref.watch(appConfigProvider) != null);

/// Sign-in (research.md R4).
///
/// Overridden at startup with [CognitoAuthSessionProvider] when [appConfigProvider]
/// is set. The default below is an in-memory stub that fabricates a `sub` and a
/// fake token: correct for tests and for a guest-only build, and never to be
/// treated as a real account — which is what [signInAvailableProvider] guards.
final authSessionProvider =
    Provider<AuthSessionProvider>((ref) => LocalAuthSessionProvider());

final accountRepositoryProvider = Provider(
  (ref) => AccountRepository(
    ref.watch(databaseProvider),
    ref.watch(authSessionProvider),
  ),
);

final isGuestProvider = FutureProvider<bool>(
  (ref) => ref.watch(accountRepositoryProvider).isGuest(),
);

/// Overridden at startup with a Dio pointed at the deployed API.
final apiClientProvider = Provider<ApiClient?>((ref) => null);

final syncWorkerProvider = Provider<SyncWorker?>((ref) {
  final api = ref.watch(apiClientProvider);
  if (api == null) return null;
  return SyncWorker(database: ref.watch(databaseProvider), api: api);
});

/// What the farmer sees about backup state (FR-053b, SC-015).
///
/// Falls back to reading the local outbox when no API is configured, so a
/// guest-only build still tells the truth about what is and is not protected.
final syncStatusProvider = FutureProvider<SyncStatus>((ref) async {
  final worker = ref.watch(syncWorkerProvider);
  if (worker != null) return worker.status();

  final db = ref.watch(databaseProvider);
  final account = await db.accountSnapshot();
  final pending = await db.pendingCount();
  if (account?.accountId == null) {
    return SyncStatus(health: SyncHealth.guest, pendingCount: pending);
  }
  return SyncStatus(
    health: pending == 0 ? SyncHealth.upToDate : SyncHealth.pending,
    pendingCount: pending,
    lastSyncedAt: account?.lastSyncedAt,
  );
});

// ---------------------------------------------------------------- fertilizer

final applicationsForCroppingProvider =
    StreamProvider.family<List<ScheduledApplicationEntity>, String>(
  (ref, croppingId) =>
      ref.watch(applicationRepositoryProvider).watchForCropping(croppingId),
);

/// research.md R9: while the shipped bundle carries stand-in figures, the app says
/// amounts are unavailable rather than presenting zeros as agronomic guidance.
final guidanceIsPlaceholderProvider = FutureProvider<bool>(
  (ref) => ref.watch(templateLookupProvider).isPlaceholder(),
);

final reminderReconciliationProvider = Provider(
  (ref) => ReminderReconciliation(
    database: ref.watch(databaseProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
    croppings: ref.watch(croppingRepositoryProvider),
    applications: ref.watch(applicationRepositoryProvider),
    fields: ref.watch(fieldRepositoryProvider),
  ),
);

/// FR-019a. Defaults to on, because a farmer who never opens settings should
/// still be reminded.
final remindersEnabledProvider = FutureProvider<bool>(
  (ref) => ref.watch(reminderReconciliationProvider).remindersEnabled(),
);

/// Whether the OS will deliver the reminders the app has scheduled.
///
/// The farmer's preference (above) and the system permission are two different
/// things, and only this one decides whether anything arrives. Asked fresh rather
/// than cached, because it can be revoked in system settings long after the app
/// last looked.
final notificationsPermittedProvider = FutureProvider<bool>(
  (ref) => ref.watch(reminderSchedulerProvider).notificationsEnabled(),
);

// ---------------------------------------------------------------- home

final homeRepositoryProvider = Provider(
  (ref) => HomeRepository(
    croppings: ref.watch(croppingRepositoryProvider),
    applications: ref.watch(applicationRepositoryProvider),
    fields: ref.watch(fieldRepositoryProvider),
    sales: ref.watch(saleRepositoryProvider),
  ),
);

/// Everything the home screen shows (FR-044 to FR-046b), computed from the local
/// database so it works offline.
final homeSummaryProvider = FutureProvider<HomeSummary>(
  (ref) => ref
      .watch(homeRepositoryProvider)
      .load(today: ref.watch(todayProvider)),
);

// ---------------------------------------------------------------- comparison

final comparisonRepositoryProvider = Provider(
  (ref) => ComparisonRepository(
    database: ref.watch(databaseProvider),
    croppings: ref.watch(croppingRepositoryProvider),
    fields: ref.watch(fieldRepositoryProvider),
    results: ref.watch(resultRepositoryProvider),
  ),
);

/// Every cropping with its result (FR-043), computed locally so comparing works
/// offline.
final comparisonRowsProvider = FutureProvider<List<ComparisonRow>>(
  (ref) => ref.watch(comparisonRepositoryProvider).load(),
);

final comparisonFilterProvider =
    StateProvider<ComparisonFilter>((ref) => const ComparisonFilter());

// ---------------------------------------------------------------- templates

final templateRepositoryProvider =
    Provider((ref) => TemplateRepository(ref.watch(databaseProvider)));

/// Every fertilizer template, for the editor (FR-024).
final templatesProvider = FutureProvider<List<TemplateRef>>(
  (ref) => ref.watch(templateRepositoryProvider).all(),
);

final templateByIdProvider = FutureProvider.family<TemplateRef?, String>(
  (ref, id) => ref.watch(templateRepositoryProvider).byId(id),
);
