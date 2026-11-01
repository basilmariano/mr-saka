import 'package:drift/drift.dart';

import '../../domain/model/calendar_date.dart';
import '../local/database.dart';
import '../local/repositories/cropping_repository.dart';
import '../local/tables.dart';
import '../remote/api_client.dart';

/// Restoring a farmer's history onto a new or reinstalled device.
///
/// FR-052, FR-064, SC-013: 100% recovery with no re-entry and no figure differing.
///
/// Two steps here are easy to forget and both are load-bearing
/// (contracts/sync-protocol.md, Restore):
///   - cropping statuses must be re-derived, or a restored cropping displays stale
///   - pending reminders must be rescheduled, or the device silently stops
///     reminding the farmer
class RestoreService {
  RestoreService({
    required SakaDatabase database,
    required ApiClient api,
    required CroppingRepository croppings,
    required Future<void> Function() rescheduleReminders,
  })  : _db = database,
        _api = api,
        _croppings = croppings,
        _rescheduleReminders = rescheduleReminders;

  final SakaDatabase _db;
  final ApiClient _api;
  final CroppingRepository _croppings;
  final Future<void> Function() _rescheduleReminders;

  /// Downloads everything and writes it locally.
  ///
  /// Returns how many records were restored, so the caller can show the farmer that
  /// their history actually came back.
  Future<int> restore({
    required String accountId,
    required CalendarDate today,
  }) async {
    var restored = 0;
    String? cursor;

    do {
      final page = await _api.getSnapshot(cursor: cursor);
      // One transaction per page: a failed page leaves the previous ones intact
      // rather than half-writing a cropping.
      await _db.transaction(() async {
        for (final record in page.records) {
          await _writeRecord(accountId, record);
          restored++;
        }
      });
      cursor = page.hasMore ? page.nextCursor : null;
    } while (cursor != null);

    await _db.update(_db.accountState).write(
          AccountStateCompanion(
            accountId: Value(accountId),
            lastSyncedAt: Value(DateTime.now().toUtc()),
          ),
        );

    // Restored rows carry whatever status they had when they were synced. A
    // cropping that crossed its tenth day in the meantime must advance now
    // (FR-011a, FR-011b) rather than displaying as still planted.
    await _croppings.refreshStatuses(today);

    // Without this a restored device has no alarms registered at all and stops
    // reminding the farmer, with nothing reporting an error (research.md R6).
    await _rescheduleReminders();

    return restored;
  }

  Future<void> _writeRecord(String accountId, Map<String, Object?> record) async {
    final entityType = record['entityType'] as String?;
    final id = record['id'] as String?;
    final body = (record['body'] as Map?)?.cast<String, Object?>() ?? const {};
    final deleted = record['deleted'] == true;
    if (entityType == null || id == null) return;

    // Restore writes directly, NOT through the outbox: these records already exist
    // in remote storage, and queueing them would push the farmer's whole history
    // straight back up again.
    switch (entityType) {
      case 'field':
        await _db.into(_db.fields).insertOnConflictUpdate(
              FieldsCompanion.insert(
                id: id,
                accountId: Value(accountId),
                name: body['name']! as String,
                areaSqm: body['areaSqm']! as int,
                location: Value(body['location'] as String?),
                notes: Value(body['notes'] as String?),
                archived: Value(body['archived'] == true),
                deleted: Value(deleted),
                updatedAt: DateTime.parse(record['updatedAt']! as String),
              ),
            );
      case 'expense':
        await _db.into(_db.expenses).insertOnConflictUpdate(
              ExpensesCompanion.insert(
                id: id,
                accountId: Value(accountId),
                croppingId: body['croppingId']! as String,
                date: body['date']! as String,
                category: CategoryDb.values.byName(body['category']! as String),
                amountCentavos: body['amountCentavos']! as int,
                notes: Value(body['notes'] as String?),
                deleted: Value(deleted),
                updatedAt: DateTime.parse(record['updatedAt']! as String),
              ),
            );
      case 'harvest':
        await _db.into(_db.harvests).insertOnConflictUpdate(
              HarvestsCompanion.insert(
                id: id,
                accountId: Value(accountId),
                croppingId: body['croppingId']! as String,
                date: body['date']! as String,
                totalWetGrams: body['totalWetGrams']! as int,
                sacks: Value(body['sacks'] as int?),
                avgWetGramsPerSack: Value(body['avgWetGramsPerSack'] as int?),
                deleted: Value(deleted),
                updatedAt: DateTime.parse(record['updatedAt']! as String),
              ),
            );
      case 'sale':
        await _db.into(_db.sales).insertOnConflictUpdate(
              SalesCompanion.insert(
                id: id,
                accountId: Value(accountId),
                croppingId: body['croppingId']! as String,
                quantityGrams: body['quantityGrams']! as int,
                pricePerKgCentavos: body['pricePerKgCentavos']! as int,
                buyer: body['buyer']! as String,
                date: body['date']! as String,
                deleted: Value(deleted),
                updatedAt: DateTime.parse(record['updatedAt']! as String),
              ),
            );
      case 'cropping':
        await _db.into(_db.croppings).insertOnConflictUpdate(
              CroppingsCompanion.insert(
                id: id,
                accountId: Value(accountId),
                fieldId: body['fieldId']! as String,
                crop: CropDb.values.byName(body['crop']! as String),
                varietyId: body['varietyId']! as String,
                plantingMethod:
                    PlantingMethodDb.values.byName(body['plantingMethod']! as String),
                growingSeason:
                    SeasonDb.values.byName(body['growingSeason']! as String),
                plantingDate: body['plantingDate']! as String,
                expectedHarvestDate: Value(body['expectedHarvestDate'] as String?),
                status: StatusDb.values.byName(body['status']! as String),
                saleWeightBasis: Value(
                  body['saleWeightBasis'] == null
                      ? null
                      : BasisDb.values.byName(body['saleWeightBasis']! as String),
                ),
                driedWeightGrams: Value(body['driedWeightGrams'] as int?),
                deleted: Value(deleted),
                updatedAt: DateTime.parse(record['updatedAt']! as String),
              ),
            );
    }
  }
}
