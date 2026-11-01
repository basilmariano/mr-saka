import 'package:drift/drift.dart';

import '../../remote/auth_session.dart';
import '../database.dart';
import '../tables.dart';
import '../write_through.dart';

/// Accounts and guest mode. FR-058 to FR-067.
class AccountRepository {
  AccountRepository(this._db, this._auth);

  final SakaDatabase _db;
  final AuthSessionProvider _auth;

  Future<AuthSession> current() => _auth.currentSession();

  Future<bool> isGuest() async => (await _auth.currentSession()).isGuest;

  /// FR-061, SC-016: signing up moves every guest record into the account.
  ///
  /// Nothing is re-keyed, because ids were client-generated from the start
  /// (contracts/sync-protocol.md I3). The farmer loses nothing and re-enters
  /// nothing — which matters because losing trial data at sign-up is the worst
  /// possible onboarding outcome.
  Future<int> adoptGuestRecords(String accountId) =>
      _db.claimGuestRecords(accountId);

  /// Sign in or sign up — the hosted page offers both, plus the forgotten-password
  /// route that satisfies FR-066, so this app needs no separate call for either.
  ///
  /// The recorded method comes back from the identity provider rather than from
  /// which button the farmer pressed: `preferGoogle` is only a hint to skip the
  /// chooser, and a farmer who lands on Google and then picks email must still be
  /// recorded as email.
  Future<AuthSession> signIn({bool preferGoogle = false}) async {
    final session = await _auth.signIn(preferGoogle: preferGoogle);
    return _afterSignIn(
      Future.value(session),
      session.method == SignInMethod.google
          ? SignInMethodDb.google
          : SignInMethodDb.email,
    );
  }

  /// FR-063: signing out must leave no records readable to a guest or another
  /// account afterwards.
  ///
  /// Local rows are cleared rather than kept: they are already in remote storage,
  /// and leaving them on the device would show one farmer's figures to whoever
  /// opens the app next.
  Future<void> signOut() async {
    await _auth.signOut();
    await _db.transaction(() async {
      for (final table in <TableInfo<Table, dynamic>>[
        _db.fields,
        _db.croppings,
        _db.scheduledApplications,
        _db.expenses,
        _db.harvests,
        _db.sales,
        _db.outbox,
      ]) {
        await _db.delete(table).go();
      }
      await _db.update(_db.accountState).write(
            const AccountStateCompanion(
              accountId: Value(null),
              signInMethod: Value(SignInMethodDb.guest),
              lastSyncedAt: Value(null),
            ),
          );
    });
  }

  Future<AuthSession> _afterSignIn(
    Future<AuthSession> signIn,
    SignInMethodDb method,
  ) async {
    final session = await signIn;
    final accountId = session.accountId;
    if (accountId == null) throw const AuthFailure('Sign-in returned no account');

    // Adopt anything entered as a guest BEFORE recording the account, so a crash
    // between the two leaves the records claimable rather than orphaned.
    await adoptGuestRecords(accountId);
    await _db.update(_db.accountState).write(
          AccountStateCompanion(
            accountId: Value(accountId),
            signInMethod: Value(method),
          ),
        );
    return session;
  }
}
