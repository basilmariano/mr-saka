import 'dart:convert';

import 'package:drift/drift.dart';

import 'database.dart';
import 'tables.dart';

/// The outbox write path.
///
/// contracts/sync-protocol.md I1: a domain write and its outbox append happen inside
/// ONE transaction. Both commit or neither does.
///
/// This is why the outbox is built in the foundational phase rather than alongside
/// sync: if stories wrote directly to tables, adding the outbox later would mean
/// touching every write path in the app. Nothing drains the outbox until the
/// durability phase — it simply accumulates.
extension WriteThrough on SakaDatabase {
  /// Performs [write] and queues the resulting record for sync, atomically.
  ///
  /// A crash between the two cannot lose the entry, nor queue a write that was never
  /// applied, because there is no "between".
  Future<T> writeAndQueue<T>({
    required String entityType,
    required String entityId,
    required OutboxOpDb operation,
    required Map<String, Object?> payload,
    required Future<T> Function() write,
  }) =>
      transaction(() async {
        final result = await write();
        await into(outbox).insert(
          OutboxCompanion.insert(
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            payload: jsonEncode(payload),
            queuedAt: DateTime.now().toUtc(),
          ),
        );
        return result;
      });

  /// Entries awaiting sync, oldest first.
  ///
  /// FR-053e: drained in strict `seq` order. Out-of-order delivery would let a stale
  /// value overwrite a correction in remote storage, leaving the farmer's durable
  /// copy wrong while the device shows the right number.
  Future<List<OutboxData>> pendingOutbox({int limit = 100}) =>
      (select(outbox)
            ..orderBy([(o) => OrderingTerm.asc(o.seq)])
            ..limit(limit))
          .get();

  /// FR-053b: how many entries are not yet protected against device loss.
  Future<int> pendingCount() async {
    final count = outbox.seq.count();
    final row = await (selectOnly(outbox)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> removeFromOutbox(Iterable<int> sequences) =>
      (delete(outbox)..where((o) => o.seq.isIn(sequences))).go();

  /// Guest-to-account migration (FR-061): claim every local row for [accountId] and
  /// queue all of them, in one transaction, without rewriting a single id.
  ///
  /// Ids were client-generated from the start, which is exactly what makes this
  /// possible — SC-016 requires the farmer keeps 100% of their trial records.
  Future<int> claimGuestRecords(String accountId) => transaction(() async {
        final tables = <TableInfo<Table, dynamic>>[
          fields,
          croppings,
          varieties,
          fertilizerTemplates,
          fertilizerTemplateSteps,
          scheduledApplications,
          expenses,
          harvests,
          sales,
        ];
        var claimed = 0;
        for (final table in tables) {
          claimed += await customUpdate(
            'UPDATE ${table.actualTableName} SET account_id = ? '
            'WHERE account_id IS NULL',
            variables: [Variable.withString(accountId)],
            updates: {table},
          );
        }
        await update(accountState)
            .write(AccountStateCompanion(accountId: Value(accountId)));
        return claimed;
      });

  /// Records a failed sync attempt so the farmer can be told (FR-053c).
  ///
  /// The entry is NOT removed. A client bug must never silently discard the
  /// farmer's data — the attempt count is what eventually surfaces the problem.
  Future<void> recordOutboxFailure(int seq, String error) =>
      customUpdate(
        'UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE seq = ?',
        variables: [Variable.withString(error), Variable.withInt(seq)],
        updates: {outbox},
      );

  /// The most-retried pending entry, which drives the "not backed up" warning.
  Future<({int attempts, String? lastError})> worstOutboxAttempts() async {
    final row = await (select(outbox)
          ..orderBy([(o) => OrderingTerm.desc(o.attempts)])
          ..limit(1))
        .getSingleOrNull();
    return (attempts: row?.attempts ?? 0, lastError: row?.lastError);
  }

  /// AccountState holds exactly one row, so this updates it without naming an id.
  Future<void> markSynced(DateTime at) => update(accountState)
      .write(AccountStateCompanion(lastSyncedAt: Value(at)));

  Future<AccountStateData?> accountSnapshot() =>
      select(accountState).getSingleOrNull();
}
