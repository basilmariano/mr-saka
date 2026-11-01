import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saka/data/local/database.dart';
import 'package:saka/data/local/tables.dart';
import 'package:saka/data/local/write_through.dart';
import 'package:saka/data/remote/api_client.dart';
import 'package:saka/data/sync/retry_policy.dart';
import 'package:saka/data/sync/sync_worker.dart';

/// contracts/sync-protocol.md I2, I3 and FR-053b, FR-053c, FR-053e.

/// Records every request so the test can assert on ordering and idempotency.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options, List<Map<String, Object?>> mutations)
      respond;
  final List<List<Map<String, Object?>>> batches = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    final data = options.data as Map<String, Object?>?;
    final mutations =
        ((data?['mutations'] as List?) ?? const []).cast<Map<String, Object?>>();
    batches.add(mutations);
    return respond(options, mutations);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, Object?> payload, {int status = 200}) =>
    ResponseBody.fromString(
      _encode(payload),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

String _encode(Map<String, Object?> payload) =>
    payload.entries.isEmpty ? '{}' : _jsonEncode(payload);

String _jsonEncode(Object? value) {
  if (value is Map) {
    return '{${value.entries.map((e) => '"${e.key}":${_jsonEncode(e.value)}').join(',')}}';
  }
  if (value is List) return '[${value.map(_jsonEncode).join(',')}]';
  if (value is String) return '"$value"';
  return '$value';
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SakaDatabase db;

  setUp(() async {
    db = SakaDatabase.memory();
    await db.update(db.accountState)
        .write(const AccountStateCompanion(accountId: Value('acct-1')));
  });
  tearDown(() => db.close());

  Future<void> queue(String id, String name) => db.writeAndQueue(
        entityType: 'field',
        entityId: id,
        operation: OutboxOpDb.upsert,
        payload: {'name': name, 'areaSqm': 25000},
        write: () => db.into(db.fields).insertOnConflictUpdate(
              FieldsCompanion.insert(
                id: id,
                name: name,
                areaSqm: 25000,
                updatedAt: DateTime.now().toUtc(),
              ),
            ),
      );

  SyncWorker workerWith(_FakeAdapter adapter, {int batchSize = 100}) {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    return SyncWorker(
      database: db,
      api: ApiClient(dio: dio),
      batchSize: batchSize,
    );
  }

  test('drains the outbox and clears it', () async {
    await queue('f1', 'Field 1');
    await queue('f2', 'Field 2');

    final adapter = _FakeAdapter((_, m) => _json({'appliedCount': m.length}));
    final outcome = await workerWith(adapter).drain();

    expect(outcome, SyncOutcome.applied);
    expect(await db.pendingCount(), 0);
  });

  test('sends mutations in strict seq order', () async {
    // FR-053e: a later correction must reach remote storage AFTER the value it
    // replaces, or the durable copy ends up wrong while the device looks right.
    await queue('f1', 'Field 1');
    await queue('f1', 'Field 1 corrected');
    await queue('f1', 'Field 1 corrected twice');

    final adapter = _FakeAdapter((_, m) => _json({'appliedCount': m.length}));
    await workerWith(adapter).drain();

    final sent = adapter.batches.first;
    final seqs = sent.map((m) => m['seq']! as int).toList();
    expect(seqs, orderedEquals([...seqs]..sort()));
    expect(
      (sent.last['body']! as Map)['name'],
      'Field 1 corrected twice',
    );
  });

  test('halts at a rejection and keeps the unsent entries queued', () async {
    // sync-protocol.md I2: never skip ahead past a failure.
    await queue('f1', 'Field 1');
    await queue('f2', 'Field 2');
    await queue('f3', 'Field 3');

    final adapter = _FakeAdapter((_, __) => _json({
          'appliedCount': 1,
          'failedIndex': 1,
          'error': {'code': 'validation_failed', 'message': 'bad record'},
        }));
    final outcome = await workerWith(adapter).drain();

    expect(outcome, SyncOutcome.rejected);
    // One applied, two still queued — and nothing was dropped.
    expect(await db.pendingCount(), 2);
  });

  test('a rejected entry is never discarded, only counted', () async {
    // FR-053c: a client bug must not silently throw away the farmer's data.
    await queue('f1', 'Field 1');
    final adapter = _FakeAdapter((_, __) => _json({
          'appliedCount': 0,
          'failedIndex': 0,
          'error': {'code': 'validation_failed', 'message': 'bad record'},
        }));

    final worker = workerWith(adapter);
    await worker.drain();
    await worker.drain();

    expect(await db.pendingCount(), 1);
    final worst = await db.worstOutboxAttempts();
    expect(worst.attempts, 2);
    expect(worst.lastError, 'bad record');
  });

  test('being offline leaves everything queued and is not a failure', () async {
    await queue('f1', 'Field 1');
    final adapter = _FakeAdapter((options, __) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ));

    final outcome = await workerWith(adapter).drain();
    expect(outcome, SyncOutcome.offline);
    expect(await db.pendingCount(), 1);
  });

  test('status reflects what is protected and what is not', () async {
    final adapter = _FakeAdapter((_, m) => _json({'appliedCount': m.length}));
    final worker = workerWith(adapter);

    expect((await worker.status()).health, SyncHealth.upToDate);

    await queue('f1', 'Field 1');
    final pending = await worker.status();
    expect(pending.health, SyncHealth.pending);
    expect(pending.pendingCount, 1);

    await worker.drain();
    final done = await worker.status();
    expect(done.health, SyncHealth.upToDate);
    expect(done.lastSyncedAt, isNotNull);
  });

  test('a guest is told their records are on this phone only', () async {
    // FR-060: a guest's records are genuinely unprotected, and the app says so.
    await db.update(db.accountState)
        .write(const AccountStateCompanion(accountId: Value(null)));

    final adapter = _FakeAdapter((_, m) => _json({'appliedCount': m.length}));
    expect((await workerWith(adapter).status()).health, SyncHealth.guest);
  });

  test('repeated failures surface as not backed up', () async {
    await queue('f1', 'Field 1');
    final adapter = _FakeAdapter((_, __) => _json({
          'appliedCount': 0,
          'failedIndex': 0,
          'error': {'code': 'validation_failed', 'message': 'bad record'},
        }));
    final worker = workerWith(adapter);
    for (var i = 0; i < 5; i++) {
      await worker.drain();
    }
    expect((await worker.status()).health, SyncHealth.notBackedUp);
  });

  test('an outage of any length never discards a queued record', () async {
    // FR-053g. With no operator alerting by design (research.md R12), the device
    // retrying IS the recovery mechanism for a server-side outage: nobody is
    // paged, so nothing else will notice. A maximum attempt count would look
    // like ordinary hygiene in review and would silently turn a recoverable
    // outage into data loss.
    await queue('f1', 'Field 1');
    await queue('f2', 'Field 2');

    var failing = true;
    final adapter = _FakeAdapter((_, m) => failing
        ? _json({'error': {'code': 'unavailable'}}, status: 503)
        : _json({'appliedCount': m.length}));
    final worker = workerWith(adapter);

    // Far past surfaceAfterAttempts (5). The farmer has long since been warned;
    // the records must still be here.
    for (var i = 0; i < 50; i++) {
      expect(await worker.drain(), SyncOutcome.retryable,
          reason: 'attempt ${i + 1} stopped retrying while the service was '
              'still down. If this reads "applied", the queue was emptied by '
              'discarding the records rather than by sending them.');
    }
    expect(await db.pendingCount(), 2,
        reason: 'a failed attempt discarded the farmer\'s record');
    expect((await worker.status()).health, SyncHealth.notBackedUp);

    // The service comes back. Nobody intervened, and nothing was re-entered.
    failing = false;
    expect(await worker.drain(), SyncOutcome.applied);
    expect(await db.pendingCount(), 0);
    expect((await worker.status()).health, SyncHealth.upToDate);
  });

  group('RetryPolicy', () {
    const policy = RetryPolicy();

    test('backs off exponentially up to the cap', () {
      expect(policy.delayForAttempt(0), const Duration(seconds: 30));
      expect(policy.delayForAttempt(1), const Duration(minutes: 1));
      expect(policy.delayForAttempt(3), const Duration(minutes: 4));
      expect(policy.delayForAttempt(99), const Duration(hours: 6));
    });

    test('the backoff stays finite however many attempts have failed', () {
      // FR-053g: there is no attempt count at which the policy stops offering a
      // delay. The cap bounds how long the farmer waits, not how long the app
      // keeps trying.
      for (final attempt in [100, 10000, 1000000]) {
        expect(policy.delayForAttempt(attempt), const Duration(hours: 6));
      }
    });

    test('the attempt count only decides when to warn, never when to stop', () {
      // shouldSurface is the ONLY attempt-based predicate on this policy, and it
      // latches on rather than flipping to a terminal state. If a give-up
      // threshold is ever added, this is where it would appear.
      expect(policy.shouldSurface(policy.surfaceAfterAttempts - 1), isFalse);
      for (final attempt in [policy.surfaceAfterAttempts, 50, 100000]) {
        expect(policy.shouldSurface(attempt), isTrue);
      }
    });

    test('only a clean apply continues the drain', () {
      expect(policy.shouldContinue(SyncOutcome.applied), isTrue);
      for (final outcome in [
        SyncOutcome.offline,
        SyncOutcome.retryable,
        SyncOutcome.unauthorized,
        SyncOutcome.rejected,
      ]) {
        expect(policy.shouldContinue(outcome), isFalse);
      }
    });
  });
}
