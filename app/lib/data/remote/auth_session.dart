/// How the farmer signed in. FR-058, FR-059.
enum SignInMethod { guest, google, email }

class AuthSession {
  const AuthSession({required this.accountId, required this.method});

  /// Cognito `sub`. Null means guest (FR-059).
  final String? accountId;
  final SignInMethod method;

  bool get isGuest => accountId == null;

  static const AuthSession guest =
      AuthSession(accountId: null, method: SignInMethod.guest);
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
}

/// Sign-in, behind an interface.
///
/// research.md R4 chose Cognito with Google first. Keeping that behind an interface
/// means the account plumbing — guest mode, migration, restore — is testable without
/// a network or an AWS account, and swapping to phone OTP in phase 2 touches only
/// the implementation.
///
/// FR-065: an existing session must keep working offline. Implementations must not
/// require a network call to report a session that is already established, or a
/// farmer would be locked out of their own records exactly when they are furthest
/// from signal.
abstract interface class AuthSessionProvider {
  Future<AuthSession> currentSession();

  /// Signs in or signs up — one call, because the farmer does not distinguish
  /// them and neither does the hosted page they land on.
  ///
  /// [preferGoogle] skips the chooser and goes straight to Google, which is the
  /// two-tap path research.md R4 expects most farmers to take. Without it the
  /// farmer gets the full page: Google, email and password, create an account,
  /// and the forgotten-password link that satisfies FR-066. There is deliberately
  /// no email/password parameter — the credentials are typed on the provider's
  /// own page and never pass through this app.
  Future<AuthSession> signIn({bool preferGoogle = false});

  Future<void> signOut();

  /// The bearer token for API calls, or null for a guest.
  ///
  /// May be null for a signed-in farmer too, when the token has expired and the
  /// device is offline. That is a reason to postpone a sync, never a reason to
  /// end the session (FR-065).
  Future<String?> accessToken();
}

/// In-memory implementation for tests and for guest-only builds.
class LocalAuthSessionProvider implements AuthSessionProvider {
  AuthSession _session = AuthSession.guest;
  String? _token;

  @override
  Future<AuthSession> currentSession() async => _session;

  @override
  Future<AuthSession> signIn({bool preferGoogle = false}) async => _establish(
        preferGoogle ? 'google-sub' : 'hosted-sub',
        preferGoogle ? SignInMethod.google : SignInMethod.email,
      );

  @override
  Future<void> signOut() async {
    _session = AuthSession.guest;
    _token = null;
  }

  @override
  Future<String?> accessToken() async => _token;

  AuthSession _establish(String sub, SignInMethod method) {
    _session = AuthSession(accountId: sub, method: method);
    _token = 'token-for-$sub';
    return _session;
  }
}
