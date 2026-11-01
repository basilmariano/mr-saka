import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/model/calendar_date.dart';
import '../../../domain/model/entities.dart';
import '../../../domain/model/grams.dart';
import '../database.dart';
import '../mappers.dart';
import '../tables.dart';
import '../write_through.dart';

/// Harvests. FR-032, FR-033.
///
/// One harvest per cropping (spec Assumptions). Recording one is what moves the
/// cropping to `harvested` — the caller is responsible for that, so the status
/// change and the harvest row stay in the repository that owns each.
class HarvestRepository {
  HarvestRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final SakaDatabase _db;
  final Uuid _uuid;

  Future<HarvestEntity?> forCropping(String croppingId) =>
      (_db.select(_db.harvests)
            ..where((h) =>
                h.croppingId.equals(croppingId) & h.deleted.equals(false)))
          .getSingleOrNull()
          .then((row) => row == null ? null : harvestFromRow(row));

  /// FR-032: either sacks x average WET kg per sack, or a total in WET kg.
  /// Harvest weight is always fresh weight (FR-032a).
  ///
  /// A total of zero is accepted — a total crop failure is a real outcome.
  Future<HarvestEntity> record({
    required String croppingId,
    required CalendarDate date,
    int? sacks,
    Grams? avgWetPerSack,
    Grams? totalWet,
  }) async {
    assert(
      totalWet != null || (sacks != null && avgWetPerSack != null),
      'Provide either a total or sacks and an average per sack',
    );
    final total = totalWet ??
        Grams(avgWetPerSack!.value * sacks!);

    final existing = await forCropping(croppingId);
    final harvest = HarvestEntity(
      id: existing?.id ?? _uuid.v4(),
      croppingId: croppingId,
      date: date,
      totalWet: total,
      sacks: sacks,
      avgWetPerSack: avgWetPerSack,
    );
    await _write(harvest);
    return harvest;
  }

  Future<void> delete(String id) => _db.writeAndQueue(
        entityType: 'harvest',
        entityId: id,
        operation: OutboxOpDb.delete,
        payload: {'id': id},
        write: () => (_db.update(_db.harvests)..where((h) => h.id.equals(id)))
            .write(const HarvestsCompanion(deleted: Value(true))),
      );

  Future<void> _write(HarvestEntity h) => _db.writeAndQueue(
        entityType: 'harvest',
        entityId: h.id,
        operation: OutboxOpDb.upsert,
        payload: {
          'id': h.id,
          'croppingId': h.croppingId,
          'date': h.date.toIso(),
          'sacks': h.sacks,
          'avgWetGramsPerSack': h.avgWetPerSack?.value,
          'totalWetGrams': h.totalWet.value,
        },
        write: () => _db.into(_db.harvests).insertOnConflictUpdate(
              HarvestsCompanion.insert(
                id: h.id,
                croppingId: h.croppingId,
                date: h.date.toIso(),
                sacks: Value(h.sacks),
                avgWetGramsPerSack: Value(h.avgWetPerSack?.value),
                totalWetGrams: h.totalWet.value,
                updatedAt: DateTime.now().toUtc(),
              ),
            ),
      );
}
