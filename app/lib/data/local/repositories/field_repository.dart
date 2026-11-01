import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/model/entities.dart';
import '../../../domain/model/square_metres.dart';
import '../database.dart';
import '../mappers.dart';
import '../tables.dart';
import '../write_through.dart';

/// Fields. FR-001 to FR-005.
class FieldRepository {
  FieldRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final SakaDatabase _db;
  final Uuid _uuid;

  Stream<List<FieldEntity>> watchActive() => (_db.select(_db.fields)
        ..where((f) => f.archived.equals(false) & f.deleted.equals(false))
        ..orderBy([(f) => OrderingTerm.asc(f.name)]))
      .watch()
      .map((rows) => rows.map(fieldFromRow).toList());

  Future<List<FieldEntity>> listActive() => (_db.select(_db.fields)
        ..where((f) => f.archived.equals(false) & f.deleted.equals(false))
        ..orderBy([(f) => OrderingTerm.asc(f.name)]))
      .get()
      .then((rows) => rows.map(fieldFromRow).toList());

  Future<FieldEntity?> byId(String id) =>
      (_db.select(_db.fields)..where((f) => f.id.equals(id)))
          .getSingleOrNull()
          .then((row) => row == null ? null : fieldFromRow(row));

  /// FR-001. The id is generated here, on the device, before the first save —
  /// which is what makes the later sync retry idempotent (sync-protocol.md I3).
  Future<FieldEntity> create({
    required String name,
    required SquareMetres area,
    String? location,
    String? notes,
  }) async {
    final field = FieldEntity(
      id: _uuid.v4(),
      name: name.trim(),
      area: area,
      location: location,
      notes: notes,
    );
    await _write(field, OutboxOpDb.upsert);
    return field;
  }

  /// FR-003.
  Future<void> update(FieldEntity field) => _write(field, OutboxOpDb.upsert);

  /// FR-004: archive rather than delete, so the cropping history survives.
  Future<void> archive(String id) async {
    final field = await byId(id);
    if (field == null) return;
    await _write(field.copyWith(archived: true), OutboxOpDb.upsert);
  }

  /// Only permitted when the field has no croppings (FR-004). Returns false when
  /// croppings exist, so the caller can offer archiving instead.
  Future<bool> deleteIfUnused(String id) async {
    final count = await (_db.select(_db.croppings)
          ..where((c) => c.fieldId.equals(id) & c.deleted.equals(false)))
        .get();
    if (count.isNotEmpty) return false;
    final field = await byId(id);
    if (field == null) return false;
    await _db.writeAndQueue(
      entityType: 'field',
      entityId: id,
      operation: OutboxOpDb.delete,
      payload: {'id': id},
      // Soft delete: a hard delete would be resurrected by the next snapshot
      // (sync-protocol.md I4).
      write: () => (_db.update(_db.fields)..where((f) => f.id.equals(id)))
          .write(const FieldsCompanion(deleted: Value(true))),
    );
    return true;
  }

  Future<void> _write(FieldEntity field, OutboxOpDb op) => _db.writeAndQueue(
        entityType: 'field',
        entityId: field.id,
        operation: op,
        payload: {
          'id': field.id,
          'name': field.name,
          'areaSqm': field.area.value,
          'location': field.location,
          'notes': field.notes,
          'archived': field.archived,
        },
        write: () => _db.into(_db.fields).insertOnConflictUpdate(
              FieldsCompanion.insert(
                id: field.id,
                name: field.name,
                areaSqm: field.area.value,
                location: Value(field.location),
                notes: Value(field.notes),
                archived: Value(field.archived),
                updatedAt: DateTime.now().toUtc(),
              ),
            ),
      );
}
