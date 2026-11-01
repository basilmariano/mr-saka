import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

/// The device's system of record.
///
/// research.md R3: FR-053 requires a save to complete locally with no network and
/// never be rejected for being offline. This database is where that save lands;
/// remote storage is the durable copy it syncs to afterwards, not the live store.
@DriftDatabase(
  tables: [
    Fields,
    Croppings,
    Varieties,
    FertilizerTemplates,
    FertilizerTemplateSteps,
    ScheduledApplications,
    Expenses,
    Harvests,
    Sales,
    Outbox,
    AccountState,
  ],
)
class SakaDatabase extends _$SakaDatabase {
  SakaDatabase(super.executor);

  /// In-memory database for tests.
  SakaDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(accountState, accountState.remindersEnabled);
          }
        },
        onCreate: (m) async {
          await m.createAll();
          // Seed the single AccountState row. The app starts as a guest
          // (FR-059): usable immediately, with no account and no remote copy.
          await into(accountState).insert(
            AccountStateCompanion.insert(signInMethod: SignInMethodDb.guest),
          );
        },
      );
}

/// Opens the on-device database file.
LazyDatabase openDatabase() => LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      return NativeDatabase.createInBackground(
        File(p.join(dir.path, 'saka.sqlite')),
      );
    });
