import 'package:drift/drift.dart';

import '../../domain/model/enums.dart';
import '../../domain/model/reference.dart';
import '../local/database.dart';
import '../local/mappers.dart';
import '../local/tables.dart';
import '../remote/api_client.dart';
import 'bundle_loader.dart';
import 'bundle_merge.dart';

/// Picks up newer published agronomic guidance. FR-026b, research.md R10.
///
/// The rule this exists to honour is FR-026c: an update replaces `seed` and
/// `published` rows and NEVER touches a row the farmer edited. A routine data
/// refresh that silently discarded the advice a farmer's local agriculturist gave
/// them is the failure most likely to destroy trust in the recommendations.
class BundleUpdater {
  BundleUpdater({required SakaDatabase database, required ApiClient api})
      : _db = database,
        _api = api;

  final SakaDatabase _db;
  final ApiClient _api;

  /// Returns the version applied, or null when nothing newer exists.
  Future<int?> checkForUpdate() async {
    final current = await _currentVersion();
    final json = await _api.getReferenceData(since: current);
    if (json == null) return null;

    final bundle = BundleLoader.parse(json);
    if (bundle.version <= current) return null;

    await apply(bundle);
    return bundle.version;
  }

  /// Applies [bundle] in ONE transaction.
  ///
  /// FR-026d: completely or not at all. A half-applied fertilizer template would
  /// produce wrong bag counts, which is worse than stale ones.
  Future<void> apply(ReferenceBundle bundle) => _db.transaction(() async {
        final existing = await _db.select(_db.varieties).get();
        final plan = BundleMerge.plan<VarietyRef>(
          existing: existing.map(_toRef),
          sourceOf: (v) => v.source,
          keyOf: (v) => v.id,
          incoming: bundle.varieties,
        );

        for (final row in plan.toRemove) {
          await (_db.delete(_db.varieties)..where((v) => v.id.equals(row.id))).go();
        }
        for (final row in plan.toApply) {
          await _db.into(_db.varieties).insertOnConflictUpdate(
                VarietiesCompanion.insert(
                  id: row.id,
                  name: row.name,
                  crop: cropToDb(row.crop),
                  maturityDays: Value(row.maturityDays),
                  source: SourceDb.published,
                  sourceAttribution: Value(row.sourceAttribution),
                  bundleVersion: Value(bundle.version),
                  updatedAt: DateTime.now().toUtc(),
                ),
              );
        }

        await _db.update(_db.accountState).write(
              AccountStateCompanion(referenceBundleVersion: Value(bundle.version)),
            );
      });

  Future<int> _currentVersion() async {
    final account = await _db.select(_db.accountState).getSingleOrNull();
    return account?.referenceBundleVersion ?? 0;
  }

  VarietyRef _toRef(Variety row) => VarietyRef(
        id: row.id,
        name: row.name,
        crop: cropFromDb(row.crop),
        maturityDays: row.maturityDays,
        source: switch (row.source) {
          SourceDb.seed => ReferenceSource.seed,
          SourceDb.published => ReferenceSource.published,
          SourceDb.farmer => ReferenceSource.farmer,
        },
        sourceAttribution: row.sourceAttribution,
        bundleVersion: row.bundleVersion,
      );
}
