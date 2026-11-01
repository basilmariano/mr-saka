import 'dart:convert';

import '../local/database.dart';
import '../local/write_through.dart';
import '../remote/api_client.dart';
import 'retry_policy.dart';

/// What the farmer is told about backup state. FR-053b, FR-053c, SC-015.
enum SyncHealth {
  /// Everything is in remote storage.
  upToDate,

  /// Entries are queued but nothing has gone wrong.
  pending,

  /// Repeated failures. The farmer must be told plainly — FR-053c forbids the app
  /// looking healthy while nothing reaches remote storage.
  notBackedUp,

  /// No account, so no remote copy at all (FR-060).
  guest,
}

class SyncStatus {
  const SyncStatus({
    required this.health,
    required this.pendingCount,
    this.lastSyncedAt,
    this.lastError,
  });

  final SyncHealth health;
  final int pendingCount;
  final DateTime? lastSyncedAt;
  final String? lastError;
}

/// Drains the outbox to remote storage.
///
/// contracts/sync-protocol.md:
///   I2 — strict `seq` order, halting rather than skipping ahead on failure.
///   I3 — idempotent, because every record carries a client-generated UUID.
///   I4 — deletes are soft, so a deletion made offline propagates.
///
/// Nothing here ever blocks a save. The farmer's write already completed locally
/// (FR-053); this is the background push to the durable copy.
class SyncWorker {
  SyncWorker({
    required SakaDatabase database,
    required ApiClient api,
    RetryPolicy policy = const RetryPolicy(),
    int batchSize = 100,
  })  : _db = database,
        _api = api,
        _policy = policy,
        _batchSize = batchSize;

  final SakaDatabase _db;
  final ApiClient _api;
  final RetryPolicy _policy;
  final int _batchSize;

  /// Drains until the outbox is empty or something stops it.
  ///
  /// Returns the outcome that ended the drain, so the caller can decide whether to
  /// back off, refresh a token, or surface a failure.
  Future<SyncOutcome> drain() async {
    while (true) {
      final batch = await _db.pendingOutbox(limit: _batchSize);
      if (batch.isEmpty) {
        await _recordSuccess();
        return SyncOutcome.applied;
      }

      final result = await _api.postMutations([
        for (final entry in batch)
          MutationPayload(
            seq: entry.seq,
            operation: entry.operation.name,
            entityType: entry.entityType,
            id: entry.entityId,
            updatedAt: entry.queuedAt,
            body: jsonDecode(entry.payload) as Map<String, Object?>,
          ),
      ]);

      // Whatever landed is removed, even on a partial failure: those mutations DID
      // apply, and re-sending them would be wasted work at best.
      if (result.appliedCount > 0) {
        await _db.removeFromOutbox(
          batch.take(result.appliedCount).map((e) => e.seq),
        );
      }

      if (result.outcome != SyncOutcome.applied) {
        // Halt. Never skip past the failure — FR-053e requires a later correction
        // to reach remote storage after the value it replaces, not before.
        await _recordFailure(batch, result);
        return result.outcome;
      }

      await _recordSuccess();
      if (batch.length < _batchSize) return SyncOutcome.applied;
    }
  }

  Future<void> _recordSuccess() async {
    await _db.markSynced(DateTime.now().toUtc());
  }

  Future<void> _recordFailure(
    List<OutboxData> batch,
    MutationResult result,
  ) async {
    final failed = batch.elementAtOrNull(result.appliedCount);
    if (failed == null) return;
    await _db.recordOutboxFailure(
      failed.seq,
      result.message ?? result.outcome.name,
    );
  }

  /// What to show the farmer, without them opening a settings screen (SC-015).
  Future<SyncStatus> status() async {
    final account = await _db.accountSnapshot();
    final pending = await _db.pendingCount();
    final worst = await _db.worstOutboxAttempts();

    if (account?.accountId == null) {
      return SyncStatus(health: SyncHealth.guest, pendingCount: pending);
    }
    if (_policy.shouldSurface(worst.attempts)) {
      return SyncStatus(
        health: SyncHealth.notBackedUp,
        pendingCount: pending,
        lastSyncedAt: account?.lastSyncedAt,
        lastError: worst.lastError,
      );
    }
    return SyncStatus(
      health: pending == 0 ? SyncHealth.upToDate : SyncHealth.pending,
      pendingCount: pending,
      lastSyncedAt: account?.lastSyncedAt,
    );
  }
}
