/// Drift table definitions. One-to-one with data-model.md.
///
/// Storage conventions, which exist to protect SC-009 (research.md R5):
///   money   -> IntColumn, centavos
///   weight  -> IntColumn, grams
///   area    -> IntColumn, square metres
///   dates   -> TextColumn, ISO-8601 calendar date, no time component
///
/// No RealColumn appears anywhere in this file, and none ever should.
library;

import 'package:drift/drift.dart';


/// Ownership and sync columns carried by every synced row.
/// `accountId` is null for a guest (FR-059, FR-060); guest-to-account migration
/// fills it in without rewriting any id (FR-061).
mixin SyncedRow on Table {
  TextColumn get id => text()();
  TextColumn get accountId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft delete. A hard delete would be resurrected by the next snapshot, because
  /// the snapshot has no way to know the row ever existed (sync-protocol.md I4).
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
}

class Fields extends Table with SyncedRow {
  TextColumn get name => text()();

  /// FR-002: must be greater than zero. Enforced in the domain layer and again here.
  IntColumn get areaSqm => integer()();
  TextColumn get location => text().nullable()();
  TextColumn get notes => text().nullable()();

  /// FR-004: a field with croppings is archived, never deleted.
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Croppings extends Table with SyncedRow {
  TextColumn get fieldId => text()();
  TextColumn get crop => textEnum<CropDb>()();
  TextColumn get varietyId => text()();
  TextColumn get plantingMethod => textEnum<PlantingMethodDb>()();

  /// When it was planted. NOT the weight basis - see `saleWeightBasis` below.
  TextColumn get growingSeason => textEnum<SeasonDb>()();

  TextColumn get plantingDate => text()();
  TextColumn get expectedHarvestDate => text().nullable()();
  BoolColumn get expectedHarvestOverridden =>
      boolean().withDefault(const Constant(false))();
  TextColumn get status => textEnum<StatusDb>()();

  /// How the produce was sold. Also "wet or dry", and entirely independent of
  /// `growingSeason` - a dry-season cropping can be sold wet. These two are never
  /// read from the same column, which is the single most likely place in this schema
  /// to introduce a silent bug (data-model.md).
  TextColumn get saleWeightBasis => textEnum<BasisDb>().nullable()();

  /// FR-034b: required once the cropping is sold dry.
  IntColumn get driedWeightGrams => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Varieties extends Table with SyncedRow {
  TextColumn get name => text()();
  TextColumn get crop => textEnum<CropDb>()();

  /// Null is meaningful: the farmer must then enter the expected harvest date
  /// manually rather than the app guessing one (spec edge case).
  IntColumn get maturityDays => integer().nullable()();

  /// research.md R9: a published bundle replaces `seed` and `published` rows and
  /// never touches `farmer` ones.
  TextColumn get source => textEnum<SourceDb>()();
  TextColumn get sourceAttribution => text().nullable()();
  IntColumn get bundleVersion => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class FertilizerTemplates extends Table with SyncedRow {
  TextColumn get crop => textEnum<CropDb>()();
  TextColumn get plantingMethod => textEnum<PlantingMethodDb>()();
  TextColumn get source => textEnum<SourceDb>()();
  TextColumn get sourceAttribution => text().nullable()();
  IntColumn get bundleVersion => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class FertilizerTemplateSteps extends Table with SyncedRow {
  TextColumn get templateId => text()();
  IntColumn get daysAfterPlanting => integer()();
  TextColumn get growthStage => text()();
  TextColumn get product => text()();
  IntColumn get ratePerHectareGrams => integer()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A template step instantiated for one cropping. FR-014.
///
/// FR-025: this is a snapshot taken when the cropping starts. Editing a template must
/// never touch an existing row here.
class ScheduledApplications extends Table with SyncedRow {
  TextColumn get croppingId => text()();
  IntColumn get daysAfterPlanting => integer()();
  TextColumn get growthStage => text()();
  TextColumn get recommendedProduct => text()();
  IntColumn get ratePerHectareGrams => integer()();
  IntColumn get sortOrder => integer()();
  TextColumn get state => textEnum<AppStateDb>()();

  // Set when done (FR-020).
  TextColumn get actualDate => text().nullable()();
  TextColumn get actualProduct => text().nullable()();
  IntColumn get actualQuantityGrams => integer().nullable()();
  IntColumn get costCentavos => integer().nullable()();
  TextColumn get skipReason => text().nullable()();

  /// FR-021: at most one expense, kept in step so the cost is never counted twice
  /// and never orphaned.
  TextColumn get linkedExpenseId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Expenses extends Table with SyncedRow {
  /// FR-031b: an expense belongs to a CROPPING, never to a field. A field can hold
  /// two open croppings at once, so a field reference would be ambiguous.
  TextColumn get croppingId => text()();

  /// May precede the planting date (land prep) and may follow the harvest date
  /// (threshing, drying, hauling). Both are normal and neither warns (FR-031a).
  TextColumn get date => text()();
  TextColumn get category => textEnum<CategoryDb>()();
  IntColumn get amountCentavos => integer()();
  TextColumn get notes => text().nullable()();

  /// Set when auto-created from a completed fertilizer application (FR-021).
  TextColumn get linkedApplicationId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Harvests extends Table with SyncedRow {
  TextColumn get croppingId => text()();
  TextColumn get date => text()();

  /// Input form, kept so the farmer's own numbers can be shown back to them.
  IntColumn get sacks => integer().nullable()();
  IntColumn get avgWetGramsPerSack => integer().nullable()();

  /// Always FRESH weight (FR-032, FR-032a). Zero is valid - a total crop failure.
  IntColumn get totalWetGrams => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Sales extends Table with SyncedRow {
  TextColumn get croppingId => text()();

  /// On the CROPPING's declared weight basis, not its own (FR-034a).
  IntColumn get quantityGrams => integer()();
  IntColumn get pricePerKgCentavos => integer()();
  TextColumn get buyer => text()();
  TextColumn get date => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The sync outbox. Local only - never leaves the device as data.
///
/// sync-protocol.md I1: a domain write and its outbox append happen in one
/// transaction, so "saved" and "queued to sync" are atomic.
class Outbox extends Table {
  /// Strict ordering (FR-053e). A later correction must never be applied before the
  /// value it replaces.
  IntColumn get seq => integer().autoIncrement()();

  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => textEnum<OutboxOpDb>()();
  TextColumn get payload => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get queuedAt => dateTime()();
}

/// Local cache of who is signed in. Not synced - it IS the Cognito user.
/// Exactly one row. Deliberately has no id column: an integer primary key is
/// aliased to rowid by SQLite, so a "singletonId defaults to 0" scheme silently
/// stores 1 and every lookup filtered on 0 matches nothing.
class AccountState extends Table {
  /// Cognito `sub`. Null means guest (FR-059).
  TextColumn get accountId => text().nullable()();
  TextColumn get signInMethod => textEnum<SignInMethodDb>()();

  /// Drives the "last successful sync" the farmer can see (FR-053b).
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  IntColumn get referenceBundleVersion => integer().withDefault(const Constant(0))();

  /// FR-019a: the farmer can turn reminders off. Defaults to on, because a farmer
  /// who never opens settings should still be reminded.
  BoolColumn get remindersEnabled => boolean().withDefault(const Constant(true))();
}

// Persisted enum names. Kept separate from the domain enums so a domain rename can
// never silently change what is already written in a farmer's database.
enum CropDb { rice, corn }

enum PlantingMethodDb { transplanted, directSeeded }

enum SeasonDb { wet, dry }

enum BasisDb { wet, dry }

enum StatusDb { planted, growing, harvested, closed }

enum AppStateDb { pending, done, skipped }

enum SourceDb { seed, published, farmer }

enum OutboxOpDb { upsert, delete }

enum SignInMethodDb { guest, google, email }

enum CategoryDb {
  landPreparation,
  seeds,
  fertilizer,
  pesticideHerbicide,
  labor,
  irrigation,
  equipmentRental,
  harvestingThreshing,
  hauling,
  other,
}
