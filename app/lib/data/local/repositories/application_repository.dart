import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/model/calendar_date.dart';
import '../../../domain/model/centavos.dart';
import '../../../domain/model/entities.dart';
import '../../../domain/model/enums.dart';
import '../../../domain/model/grams.dart';
import '../../../domain/model/reference.dart';
import '../database.dart';
import '../mappers.dart';
import '../tables.dart';
import '../write_through.dart';
import 'expense_repository.dart';

/// Fertilizer schedules. FR-014 to FR-023.
class ApplicationRepository {
  ApplicationRepository(
    this._db, {
    required ExpenseRepository expenses,
    Uuid? uuid,
  })  : _expenses = expenses,
        _uuid = uuid ?? const Uuid();

  final SakaDatabase _db;
  final ExpenseRepository _expenses;
  final Uuid _uuid;

  Future<List<ScheduledApplicationEntity>> forCropping(String croppingId) =>
      (_db.select(_db.scheduledApplications)
            ..where((a) =>
                a.croppingId.equals(croppingId) & a.deleted.equals(false))
            ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]))
          .get()
          .then((rows) => rows.map(applicationFromRow).toList());

  Stream<List<ScheduledApplicationEntity>> watchForCropping(String croppingId) =>
      (_db.select(_db.scheduledApplications)
            ..where((a) =>
                a.croppingId.equals(croppingId) & a.deleted.equals(false))
            ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]))
          .watch()
          .map((rows) => rows.map(applicationFromRow).toList());

  Future<ScheduledApplicationEntity?> byId(String id) =>
      (_db.select(_db.scheduledApplications)..where((a) => a.id.equals(id)))
          .getSingleOrNull()
          .then((row) => row == null ? null : applicationFromRow(row));

  /// FR-014: generate a cropping's schedule from the matching template.
  ///
  /// Every field is copied, not referenced. FR-025 requires the schedule to be a
  /// snapshot, so later template edits cannot reach a running cropping.
  Future<List<ScheduledApplicationEntity>> generate({
    required String croppingId,
    required TemplateRef template,
  }) async {
    final created = <ScheduledApplicationEntity>[];
    for (final step in template.steps) {
      final application = ScheduledApplicationEntity(
        id: _uuid.v4(),
        croppingId: croppingId,
        daysAfterPlanting: step.daysAfterPlanting,
        growthStage: step.growthStage,
        recommendedProduct: step.product,
        ratePerHectare: step.ratePerHectare,
        sortOrder: step.sortOrder,
        state: ApplicationState.pending,
      );
      await _write(application);
      created.add(application);
    }
    return created;
  }

  /// FR-020, FR-021.
  ///
  /// Recording a cost creates exactly ONE expense in the fertilizer category, and
  /// editing the cost later updates that same expense rather than adding another.
  /// SC-006 asserts the total moves by the difference, not by the full amount — a
  /// second expense here would silently overstate the farmer's season.
  Future<ScheduledApplicationEntity> markDone({
    required String applicationId,
    required CalendarDate actualDate,
    required String actualProduct,
    required Grams actualQuantity,
    Centavos? cost,
  }) async {
    final existing = await byId(applicationId);
    if (existing == null) throw StateError('No application $applicationId');

    String? expenseId = existing.linkedExpenseId;

    if (cost != null && cost.isPositive) {
      if (expenseId == null) {
        final expense = await _expenses.create(
          croppingId: existing.croppingId,
          date: actualDate,
          category: ExpenseCategory.fertilizer,
          amount: cost,
          linkedApplicationId: applicationId,
        );
        expenseId = expense.id;
      } else {
        final linked = await _expenses.byLinkedApplication(applicationId);
        if (linked != null) {
          await _expenses.update(
            ExpenseEntity(
              id: linked.id,
              croppingId: linked.croppingId,
              date: actualDate,
              category: ExpenseCategory.fertilizer,
              amount: cost,
              notes: linked.notes,
              linkedApplicationId: applicationId,
            ),
          );
        }
      }
    } else if (expenseId != null) {
      // The cost was cleared. The expense must go with it, or the farmer is left
      // paying for a fertilizer application they recorded as free.
      await _expenses.delete(expenseId);
      expenseId = null;
    }

    final updated = existing.copyWith(
      state: ApplicationState.done,
      actualDate: actualDate,
      actualProduct: actualProduct,
      actualQuantity: actualQuantity,
      cost: cost,
      linkedExpenseId: expenseId,
      clearLink: expenseId == null,
    );
    await _write(updated);
    return updated;
  }

  /// FR-022: skipped, with an optional reason and no expense.
  Future<void> markSkipped({
    required String applicationId,
    String? reason,
  }) async {
    final existing = await byId(applicationId);
    if (existing == null) return;
    if (existing.linkedExpenseId != null) {
      await _expenses.delete(existing.linkedExpenseId!);
    }
    await _write(
      existing.copyWith(
        state: ApplicationState.skipped,
        skipReason: reason,
        clearLink: true,
      ),
    );
  }

  /// Returns a completed application to pending, removing any expense it created.
  Future<void> markPending(String applicationId) async {
    final existing = await byId(applicationId);
    if (existing == null) return;
    if (existing.linkedExpenseId != null) {
      await _expenses.delete(existing.linkedExpenseId!);
    }
    await _write(
      existing.copyWith(state: ApplicationState.pending, clearLink: true),
    );
  }

  /// FR-023: edit a cropping's own schedule without touching the template.
  Future<ScheduledApplicationEntity> addStep({
    required String croppingId,
    required int daysAfterPlanting,
    required String growthStage,
    required String product,
    required Grams ratePerHectare,
    required int sortOrder,
  }) async {
    final application = ScheduledApplicationEntity(
      id: _uuid.v4(),
      croppingId: croppingId,
      daysAfterPlanting: daysAfterPlanting,
      growthStage: growthStage,
      recommendedProduct: product,
      ratePerHectare: ratePerHectare,
      sortOrder: sortOrder,
      state: ApplicationState.pending,
    );
    await _write(application);
    return application;
  }

  Future<void> update(ScheduledApplicationEntity application) =>
      _write(application);

  /// FR-021: deleting an application takes its expense with it, so a cost is never
  /// orphaned on the cropping with nothing to explain it.
  Future<void> delete(String applicationId) async {
    final existing = await byId(applicationId);
    if (existing?.linkedExpenseId != null) {
      await _expenses.delete(existing!.linkedExpenseId!);
    }
    await _db.writeAndQueue(
      entityType: 'scheduledApplication',
      entityId: applicationId,
      operation: OutboxOpDb.delete,
      payload: {'id': applicationId, 'croppingId': existing?.croppingId},
      write: () => (_db.update(_db.scheduledApplications)
            ..where((a) => a.id.equals(applicationId)))
          .write(const ScheduledApplicationsCompanion(deleted: Value(true))),
    );
  }

  /// FR-011a: whether any application on this cropping is done, which is one of the
  /// two triggers that move it from planted to growing.
  Future<bool> anyDone(String croppingId) async {
    final rows = await (_db.select(_db.scheduledApplications)
          ..where((a) =>
              a.croppingId.equals(croppingId) &
              a.state.equalsValue(AppStateDb.done) &
              a.deleted.equals(false))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  Future<void> _write(ScheduledApplicationEntity a) => _db.writeAndQueue(
        entityType: 'scheduledApplication',
        entityId: a.id,
        operation: OutboxOpDb.upsert,
        payload: {
          'id': a.id,
          'croppingId': a.croppingId,
          'daysAfterPlanting': a.daysAfterPlanting,
          'growthStage': a.growthStage,
          'recommendedProduct': a.recommendedProduct,
          'ratePerHectareGrams': a.ratePerHectare.value,
          'sortOrder': a.sortOrder,
          'state': a.state.name,
          'actualDate': a.actualDate?.toIso(),
          'actualProduct': a.actualProduct,
          'actualQuantityGrams': a.actualQuantity?.value,
          'costCentavos': a.cost?.value,
          'skipReason': a.skipReason,
          'linkedExpenseId': a.linkedExpenseId,
        },
        write: () => _db.into(_db.scheduledApplications).insertOnConflictUpdate(
              ScheduledApplicationsCompanion.insert(
                id: a.id,
                croppingId: a.croppingId,
                daysAfterPlanting: a.daysAfterPlanting,
                growthStage: a.growthStage,
                recommendedProduct: a.recommendedProduct,
                ratePerHectareGrams: a.ratePerHectare.value,
                sortOrder: a.sortOrder,
                state: appStateToDb(a.state),
                actualDate: Value(a.actualDate?.toIso()),
                actualProduct: Value(a.actualProduct),
                actualQuantityGrams: Value(a.actualQuantity?.value),
                costCentavos: Value(a.cost?.value),
                skipReason: Value(a.skipReason),
                linkedExpenseId: Value(a.linkedExpenseId),
                updatedAt: DateTime.now().toUtc(),
              ),
            ),
      );
}
