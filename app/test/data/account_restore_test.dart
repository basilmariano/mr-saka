import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:saka/data/local/database.dart';
import 'package:saka/data/local/repositories/account_repository.dart';
import 'package:saka/data/local/repositories/cropping_repository.dart';
import 'package:saka/data/local/repositories/expense_repository.dart';
import 'package:saka/data/local/repositories/field_repository.dart';
import 'package:saka/data/local/tables.dart';
import 'package:saka/data/local/write_through.dart';
import 'package:saka/data/remote/api_client.dart';
import 'package:saka/data/remote/auth_session.dart';
import 'package:saka/data/sync/restore.dart';
import 'package:saka/domain/model/calendar_date.dart';
import 'package:saka/domain/model/centavos.dart';
import 'package:saka/domain/model/enums.dart';
import 'package:saka/domain/model/square_metres.dart';

class _SnapshotAdapter implements HttpClientAdapter {
  _SnapshotAdapter(this.payload);
  final String payload;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? _, Future<void>? __) async =>
      ResponseBody.fromString(payload, 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SakaDatabase db;
  late FieldRepository fields;
  late CroppingRepository croppings;
  late ExpenseRepository expenses;
  late AccountRepository accounts;
  late LocalAuthSessionProvider auth;

  const today = CalendarDate(2026, 3, 1);

  setUp(() async {
    db = SakaDatabase.memory();
    fields = FieldRepository(db);
    croppings = CroppingRepository(db);
    expenses = ExpenseRepository(db);
    auth = LocalAuthSessionProvider();
    accounts = AccountRepository(db, auth);
    await db.into(db.varieties).insert(
          VarietiesCompanion.insert(
            id: 'v1',
            name: 'NSIC Rc222',
            crop: CropDb.rice,
            maturityDays: const Value(110),
            source: SourceDb.seed,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  });
  tearDown(() => db.close());

  Future<String> seedGuestSeason() async {
    final field = await fields.create(
      name: 'Field 1',
      area: SquareMetres.parseHectares('2.5'),
    );
    final cropping = await croppings.start(
      fieldId: field.id,
      crop: Crop.rice,
      varietyId: 'v1',
      varietyMaturityDays: 110,
      plantingMethod: PlantingMethod.transplanted,
      growingSeason: GrowingSeason.wet,
      plantingDate: today,
      today: today,
    );
    await expenses.create(
      croppingId: cropping.id,
      date: today,
      category: ExpenseCategory.labor,
      amount: Centavos.fromPesos(3500),
    );
    return cropping.id;
  }

  group('Guest mode (FR-059, FR-060)', () {
    test('the app starts as a guest with no account', () async {
      expect(await accounts.isGuest(), isTrue);
      expect((await db.accountSnapshot())!.accountId, isNull);
    });

    test('a guest can record a full season with no account', () async {
      // FR-059: every feature is available to a guest on that device.
      final croppingId = await seedGuestSeason();
      expect((await expenses.total(croppingId)).format(), '3,500.00');
      expect(await fields.listActive(), hasLength(1));
    });
  });

  group('Guest to account migration (FR-061, SC-016)', () {
    test('every guest record moves into the account, nothing re-entered', () async {
      final croppingId = await seedGuestSeason();
      final before = await db.select(db.fields).get();

      final session = await accounts.signIn(preferGoogle: true);

      final after = await db.select(db.fields).get();
      expect(session.accountId, isNotNull);
      // SC-016: 100% of trial records kept, ids unchanged, figures unchanged.
      expect(after.map((f) => f.id).toList(), before.map((f) => f.id).toList());
      expect(after.every((f) => f.accountId == session.accountId), isTrue);
      expect((await expenses.total(croppingId)).format(), '3,500.00');
    });

    test('croppings and expenses are claimed too, not just fields', () async {
      await seedGuestSeason();
      final session = await accounts.signIn(preferGoogle: true);

      final crops = await db.select(db.croppings).get();
      final exps = await db.select(db.expenses).get();
      expect(crops.every((c) => c.accountId == session.accountId), isTrue);
      expect(exps.every((e) => e.accountId == session.accountId), isTrue);
    });

    test('migrated records are queued so they reach remote storage', () async {
      await seedGuestSeason();
      final queuedBefore = await db.pendingCount();
      await accounts.signIn(preferGoogle: true);
      // Nothing is lost from the queue; the guest's writes still need pushing.
      expect(await db.pendingCount(), greaterThanOrEqualTo(queuedBefore));
    });
  });

  group('Sign out (FR-063)', () {
    test('leaves no records readable to whoever opens the app next', () async {
      await seedGuestSeason();
      await accounts.signIn(preferGoogle: true);
      await accounts.signOut();

      expect(await db.select(db.fields).get(), isEmpty);
      expect(await db.select(db.croppings).get(), isEmpty);
      expect(await db.select(db.expenses).get(), isEmpty);
      expect((await db.accountSnapshot())!.accountId, isNull);
      expect(await accounts.isGuest(), isTrue);
    });
  });

  group('Restore on a new device (FR-052, FR-064, SC-013)', () {
    test('recovers the full history, re-derives status, reschedules reminders',
        () async {
      var rescheduled = false;
      const payload = '''
{"records":[
 {"entityType":"field","id":"f1","updatedAt":"2026-03-01T00:00:00.000Z","deleted":false,
  "body":{"name":"Field 1","areaSqm":25000}},
 {"entityType":"cropping","id":"c1","updatedAt":"2026-03-01T00:00:00.000Z","deleted":false,
  "body":{"fieldId":"f1","crop":"rice","varietyId":"v1","plantingMethod":"transplanted",
          "growingSeason":"wet","plantingDate":"2026-03-01","status":"planted"}},
 {"entityType":"expense","id":"e1","updatedAt":"2026-03-01T00:00:00.000Z","deleted":false,
  "body":{"croppingId":"c1","date":"2026-03-01","category":"labor","amountCentavos":350000}}
],"hasMore":false,"serverTime":"2026-03-15T00:00:00.000Z"}''';

      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _SnapshotAdapter(payload);
      final service = RestoreService(
        database: db,
        api: ApiClient(dio: dio),
        croppings: croppings,
        rescheduleReminders: () async => rescheduled = true,
      );

      // Restored 14 days after planting, so the cropping must advance.
      final restored = await service.restore(
        accountId: 'acct-1',
        today: const CalendarDate(2026, 3, 15),
      );

      expect(restored, 3);
      expect(await fields.listActive(), hasLength(1));
      expect((await expenses.total('c1')).format(), '3,500.00');

      // FR-011a/b: a cropping that crossed day 10 while the device was gone must
      // not come back still displaying as planted.
      expect((await croppings.byId('c1'))!.status, CroppingStatus.growing);

      // research.md R6: without this a restored device silently stops reminding.
      expect(rescheduled, isTrue);

      expect((await db.accountSnapshot())!.lastSyncedAt, isNotNull);
    });

    test('restore does not re-queue the history it just downloaded', () async {
      const payload = '''
{"records":[{"entityType":"field","id":"f1","updatedAt":"2026-03-01T00:00:00.000Z",
 "deleted":false,"body":{"name":"Field 1","areaSqm":25000}}],
 "hasMore":false,"serverTime":"2026-03-01T00:00:00.000Z"}''';
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _SnapshotAdapter(payload);
      final service = RestoreService(
        database: db,
        api: ApiClient(dio: dio),
        croppings: croppings,
        rescheduleReminders: () async {},
      );

      await service.restore(accountId: 'acct-1', today: today);

      // These records already exist remotely; queueing them would push the whole
      // history straight back up again.
      expect(await db.pendingCount(), 0);
    });
  });
}
