import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/calc/money_calc.dart';
import '../../../domain/model/calendar_date.dart';
import '../../../domain/model/centavos.dart';
import '../../../domain/model/entities.dart';
import '../../../domain/model/enums.dart';
import '../database.dart';
import '../mappers.dart';
import '../tables.dart';
import '../write_through.dart';

/// Expenses. FR-027 to FR-031c.
class ExpenseRepository {
  ExpenseRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final SakaDatabase _db;
  final Uuid _uuid;

  Future<List<ExpenseEntity>> forCropping(String croppingId) =>
      (_db.select(_db.expenses)
            ..where((e) =>
                e.croppingId.equals(croppingId) & e.deleted.equals(false))
            ..orderBy([(e) => OrderingTerm.desc(e.date)]))
          .get()
          .then((rows) => rows.map(expenseFromRow).toList());

  Stream<List<ExpenseEntity>> watchForCropping(String croppingId) =>
      (_db.select(_db.expenses)
            ..where((e) =>
                e.croppingId.equals(croppingId) & e.deleted.equals(false))
            ..orderBy([(e) => OrderingTerm.desc(e.date)]))
          .watch()
          .map((rows) => rows.map(expenseFromRow).toList());

  /// FR-029: running total for a cropping.
  Future<Centavos> total(String croppingId) async {
    final expenses = await forCropping(croppingId);
    return MoneyCalc.totalExpenses(expenses.map((e) => e.amount));
  }

  /// FR-030: breakdown by category with each category's share.
  Future<List<CategoryShare>> breakdown(String croppingId) async {
    final expenses = await forCropping(croppingId);
    final byCategory = <ExpenseCategory, Centavos>{};
    for (final expense in expenses) {
      byCategory[expense.category] =
          (byCategory[expense.category] ?? Centavos.zero) + expense.amount;
    }
    return MoneyCalc.categoryBreakdown(byCategory);
  }

  /// FR-027, FR-031a.
  ///
  /// Note what is NOT checked: the date. An expense may precede the planting date
  /// (land preparation) or follow the harvest date (threshing, drying, hauling).
  /// Both are normal practice and neither warns.
  Future<ExpenseEntity> create({
    required String croppingId,
    required CalendarDate date,
    required ExpenseCategory category,
    required Centavos amount,
    String? notes,
    String? linkedApplicationId,
  }) async {
    final expense = ExpenseEntity(
      id: _uuid.v4(),
      croppingId: croppingId,
      date: date,
      category: category,
      amount: amount,
      notes: notes,
      linkedApplicationId: linkedApplicationId,
    );
    await _write(expense);
    return expense;
  }

  Future<void> update(ExpenseEntity expense) => _write(expense);

  Future<void> delete(String id) => _db.writeAndQueue(
        entityType: 'expense',
        entityId: id,
        operation: OutboxOpDb.delete,
        payload: {'id': id},
        write: () => (_db.update(_db.expenses)..where((e) => e.id.equals(id)))
            .write(const ExpensesCompanion(deleted: Value(true))),
      );

  /// FR-021: the expense created by a completed fertilizer application.
  Future<ExpenseEntity?> byLinkedApplication(String applicationId) =>
      (_db.select(_db.expenses)
            ..where((e) =>
                e.linkedApplicationId.equals(applicationId) &
                e.deleted.equals(false)))
          .getSingleOrNull()
          .then((row) => row == null ? null : expenseFromRow(row));

  Future<void> _write(ExpenseEntity e) => _db.writeAndQueue(
        entityType: 'expense',
        entityId: e.id,
        operation: OutboxOpDb.upsert,
        payload: {
          'id': e.id,
          'croppingId': e.croppingId,
          'date': e.date.toIso(),
          'category': e.category.name,
          'amountCentavos': e.amount.value,
          'notes': e.notes,
          'linkedApplicationId': e.linkedApplicationId,
        },
        write: () => _db.into(_db.expenses).insertOnConflictUpdate(
              ExpensesCompanion.insert(
                id: e.id,
                croppingId: e.croppingId,
                date: e.date.toIso(),
                category: categoryToDb(e.category),
                amountCentavos: e.amount.value,
                notes: Value(e.notes),
                linkedApplicationId: Value(e.linkedApplicationId),
                updatedAt: DateTime.now().toUtc(),
              ),
            ),
      );
}
