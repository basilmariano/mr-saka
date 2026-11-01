import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:saka/data/local/database.dart';
import 'package:saka/data/local/tables.dart';
import 'package:saka/data/local/write_through.dart';

/// contracts/sync-protocol.md I1, I2 and FR-053d, FR-053e.
void main() {
  // This suite deliberately opens the database twice to test the restart path, which
  // drift otherwise warns about. The warning is right in production and wrong here.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SakaDatabase db;

  setUp(() => db = SakaDatabase.memory());
  tearDown(() => db.close());

  Future<void> insertField(String id, String name) => db.writeAndQueue(
        entityType: 'field',
        entityId: id,
        operation: OutboxOpDb.upsert,
        payload: {'id': id, 'name': name, 'areaSqm': 25000},
        write: () => db.into(db.fields).insert(
              FieldsCompanion.insert(
                id: id,
                name: name,
                areaSqm: 25000,
                updatedAt: DateTime.now().toUtc(),
              ),
            ),
      );

  test('a write and its outbox append are atomic', () async {
    await insertField('f1', 'Field 1');

    final fields = await db.select(db.fields).get();
    final queued = await db.pendingOutbox();

    expect(fields, hasLength(1));
    expect(queued, hasLength(1));
    expect(queued.single.entityId, 'f1');
    expect(queued.single.operation, OutboxOpDb.upsert);
  });

  test('a failed write queues nothing — there is no "between"', () async {
    // If the domain write throws, the outbox append must roll back with it.
    // Otherwise sync would push a record the device never actually saved.
    await expectLater(
      db.writeAndQueue<void>(
        entityType: 'field',
        entityId: 'f-bad',
        operation: OutboxOpDb.upsert,
        payload: const {'id': 'f-bad'},
        write: () async => throw StateError('simulated failure mid-write'),
      ),
      throwsStateError,
    );

    expect(await db.select(db.fields).get(), isEmpty);
    expect(await db.pendingOutbox(), isEmpty);
  });

  test('outbox drains in strict insertion order', () async {
    // FR-053e: a later correction must never be applied before the value it
    // replaces. Order is the only thing that guarantees this.
    for (var i = 1; i <= 5; i++) {
      await insertField('f$i', 'Field $i');
    }
    final queued = await db.pendingOutbox();
    expect(queued.map((e) => e.entityId).toList(),
        ['f1', 'f2', 'f3', 'f4', 'f5']);
    expect(
      queued.map((e) => e.seq).toList(),
      orderedEquals(List<int>.from(queued.map((e) => e.seq))..sort()),
    );
  });

  test('a correction queues after the value it replaces', () async {
    await insertField('f1', 'Field 1');
    await db.writeAndQueue(
      entityType: 'field',
      entityId: 'f1',
      operation: OutboxOpDb.upsert,
      payload: const {'id': 'f1', 'name': 'Field 1 corrected'},
      write: () => (db.update(db.fields)..where((f) => f.id.equals('f1')))
          .write(const FieldsCompanion(name: Value('Field 1 corrected'))),
    );

    final queued = await db.pendingOutbox();
    expect(queued, hasLength(2));
    expect(queued.first.seq, lessThan(queued.last.seq));
    expect(
      (jsonDecode(queued.last.payload) as Map)['name'],
      'Field 1 corrected',
    );
  });

  test('pending entries survive closing and reopening the database file', () async {
    // FR-053d: pending entries survive app and device restarts. Uses a real file and
    // genuinely closes the first connection, so this exercises the restart path
    // rather than two handles on one in-memory executor.
    final dir = await Directory.systemTemp.createTemp('saka_outbox_test');
    final file = File(p.join(dir.path, 'saka.sqlite'));

    final first = SakaDatabase(NativeDatabase(file));
    await first.writeAndQueue(
      entityType: 'field',
      entityId: 'f1',
      operation: OutboxOpDb.upsert,
      payload: const {'id': 'f1'},
      write: () => first.into(first.fields).insert(
            FieldsCompanion.insert(
              id: 'f1',
              name: 'Field 1',
              areaSqm: 25000,
              updatedAt: DateTime.now().toUtc(),
            ),
          ),
    );
    await first.close();

    final reopened = SakaDatabase(NativeDatabase(file));
    expect(await reopened.pendingCount(), 1);
    expect((await reopened.select(reopened.fields).get()).single.name, 'Field 1');
    await reopened.close();
    await dir.delete(recursive: true);
  });

  test('removing synced entries leaves the rest queued', () async {
    for (var i = 1; i <= 3; i++) {
      await insertField('f$i', 'Field $i');
    }
    final queued = await db.pendingOutbox();
    await db.removeFromOutbox([queued[0].seq, queued[1].seq]);

    final remaining = await db.pendingOutbox();
    expect(remaining, hasLength(1));
    expect(remaining.single.entityId, 'f3');
  });

  test('guest sign-up claims every local row without rewriting any id', () async {
    // FR-061 / SC-016: the farmer keeps 100% of their trial records.
    await insertField('f1', 'Field 1');
    await insertField('f2', 'Field 2');

    final claimed = await db.claimGuestRecords('cognito-sub-123');

    final fields = await db.select(db.fields).get();
    expect(claimed, 2);
    expect(fields.map((f) => f.id).toList(), ['f1', 'f2']); // ids unchanged
    expect(fields.every((f) => f.accountId == 'cognito-sub-123'), isTrue);
  });
}
