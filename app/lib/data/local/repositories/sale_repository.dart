import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/calc/money_calc.dart';
import '../../../domain/model/calendar_date.dart';
import '../../../domain/model/centavos.dart';
import '../../../domain/model/entities.dart';
import '../../../domain/model/enums.dart';
import '../../../domain/model/grams.dart';
import '../../../domain/rules/weight_basis.dart';
import '../database.dart';
import '../mappers.dart';
import '../tables.dart';
import '../write_through.dart';

/// Thrown when a sale would break FR-037.
class SaleRejected implements Exception {
  const SaleRejected(this.reason, {this.remaining});
  final SaleRejection reason;

  /// Shown to the farmer when the sale exceeds what is left.
  final Lot? remaining;
}

/// Sales. FR-034 to FR-038b.
class SaleRepository {
  SaleRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final SakaDatabase _db;
  final Uuid _uuid;

  Future<List<SaleEntity>> forCropping(String croppingId) =>
      (_db.select(_db.sales)
            ..where((s) =>
                s.croppingId.equals(croppingId) & s.deleted.equals(false))
            ..orderBy([(s) => OrderingTerm.desc(s.date)]))
          .get()
          .then((rows) => rows.map(saleFromRow).toList());

  /// FR-035: revenue is the sum across sales.
  Future<Centavos> revenue(String croppingId) async {
    final sales = await forCropping(croppingId);
    return MoneyCalc.totalRevenue(
      sales.map(
        (s) => MoneyCalc.saleRevenue(quantity: s.quantity, pricePerKg: s.pricePerKg),
      ),
    );
  }

  /// FR-034c: the quantity available to sell, on the cropping's own basis.
  ///
  /// Null when the cropping is sold dry and the dried weight has not been recorded.
  Future<Lot?> sellable(CroppingEntity cropping) async {
    final harvest = await (_db.select(_db.harvests)
          ..where((h) =>
              h.croppingId.equals(cropping.id) & h.deleted.equals(false)))
        .getSingleOrNull();
    if (harvest == null) return null;
    return WeightBasisRules.sellableQuantity(
      freshHarvest: Grams(harvest.totalWetGrams),
      // Before the farmer declares a basis, the lot is assumed to be sold wet —
      // which is the overwhelmingly common case, and is confirmed on first sale.
      basis: cropping.saleWeightBasis ?? WeightBasis.wet,
      driedWeight: cropping.driedWeight,
    );
  }

  /// FR-036: remaining unsold quantity, both sides on the same basis.
  Future<Lot?> remaining(CroppingEntity cropping) async {
    final lot = await sellable(cropping);
    if (lot == null) return null;
    final sales = await forCropping(cropping.id);
    return WeightBasisRules.remainingQuantity(
      sellable: lot,
      soldQuantities: sales.map((s) => s.quantity),
    );
  }

  /// FR-034, FR-037. Throws [SaleRejected] rather than silently clamping.
  Future<SaleEntity> record({
    required CroppingEntity cropping,
    required Grams quantity,
    required Centavos pricePerKg,
    required String buyer,
    required CalendarDate date,
  }) async {
    final harvest = await (_db.select(_db.harvests)
          ..where((h) =>
              h.croppingId.equals(cropping.id) & h.deleted.equals(false)))
        .getSingleOrNull();
    final lot = await sellable(cropping);
    final left = await remaining(cropping);

    final rejection = SaleRules.validate(
      hasHarvest: harvest != null,
      sellable: lot,
      remaining: left,
      quantity: quantity,
    );
    if (rejection != null) throw SaleRejected(rejection, remaining: left);

    final sale = SaleEntity(
      id: _uuid.v4(),
      croppingId: cropping.id,
      quantity: quantity,
      pricePerKg: pricePerKg,
      buyer: buyer.trim(),
      date: date,
    );
    await _write(sale);
    return sale;
  }

  Future<void> delete(String id) => _db.writeAndQueue(
        entityType: 'sale',
        entityId: id,
        operation: OutboxOpDb.delete,
        payload: {'id': id},
        write: () => (_db.update(_db.sales)..where((s) => s.id.equals(id)))
            .write(const SalesCompanion(deleted: Value(true))),
      );

  Future<void> _write(SaleEntity s) => _db.writeAndQueue(
        entityType: 'sale',
        entityId: s.id,
        operation: OutboxOpDb.upsert,
        payload: {
          'id': s.id,
          'croppingId': s.croppingId,
          'quantityGrams': s.quantity.value,
          'pricePerKgCentavos': s.pricePerKg.value,
          'buyer': s.buyer,
          'date': s.date.toIso(),
        },
        write: () => _db.into(_db.sales).insertOnConflictUpdate(
              SalesCompanion.insert(
                id: s.id,
                croppingId: s.croppingId,
                quantityGrams: s.quantity.value,
                pricePerKgCentavos: s.pricePerKg.value,
                buyer: s.buyer,
                date: s.date.toIso(),
                updatedAt: DateTime.now().toUtc(),
              ),
            ),
      );
}
