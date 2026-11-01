import 'dart:convert';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_config.dart';
import 'auth_session.dart';

/// Sign-in against Cognito's hosted UI. research.md R4, FR-058, FR-065, FR-066.
///
/// Authorization code + PKCE through the system browser, which is what a public
/// client must use: the app ships on the handset and can hold no secret, so there
/// is no client secret and no implicit flow putting a token in a redirect URL.
/// The farmer's password is typed on Cognito's page and never passes through this
/// app — which also means a bug here cannot leak one.
///
/// Google and email/password are the same flow. [signIn] with `preferGoogle` only
/// adds `identity_provider=Google`, which tells the hosted page to skip its own
/// chooser; everything downstream is identical.
///
/// **FR-065 shapes the whole class.** A farmer in a field with no signal must not
/// be logged out of their own records. So: the session lives in secure storage and
/// [currentSession] reads it with no network call; an expired access token is a
/// reason to postpone a sync, never to end a session; and a failed refresh keeps
/// the session rather than discarding it. Only [signOut] ends a session.
class CognitoAuthSessionProvider implements AuthSessionProvider {
  CognitoAuthSessionProvider({
    required AppConfig config,
    FlutterAppAuth? appAuth,
    FlutterSecureStorage? storage,
  })  : _config = config,
        _appAuth = appAuth ?? const FlutterAppAuth(),
        _storage = storage ?? const FlutterSecureStorage();

  final AppConfig _config;
  final FlutterAppAuth _appAuth;
  final FlutterSecureStorage _storage;

  static const _kRefreshToken = 'saka.refresh_token';
  static const _kAccessToken = 'saka.access_token';
  static const _kAccessExpiry = 'saka.access_expiry';
  static const _kSub = 'saka.sub';
  static const _kMethod = 'saka.method';

  /// Endpoints given explicitly rather than discovered. Discovery is one more
  /// network round trip that can fail, on a path where failing means the farmer
  /// cannot sign in at all — and Cognito's endpoints are a fixed shape off the
  /// hosted domain, so there is nothing to discover.
  AuthorizationServiceConfiguration get _service =>
      AuthorizationServiceConfiguration(
        authorizationEndpoint: 'https://${_config.hostedUiDomain}/oauth2/authorize',
        tokenEndpoint: 'https://${_config.hostedUiDomain}/oauth2/token',
        endSessionEndpoint: 'https://${_config.hostedUiDomain}/logout',
      );

  @override
  Future<AuthSession> currentSession() async {
    final sub = await _storage.read(key: _kSub);
    if (sub == null) return AuthSession.guest;
    final method = await _storage.read(key: _kMethod);
    return AuthSession(
      accountId: sub,
      method: method == SignInMethod.google.name
          ? SignInMethod.google
          : SignInMethod.email,
    );
  }

  @override
  Future<AuthSession> signIn({bool preferGoogle = false}) async {
    final AuthorizationTokenResponse result;
    try {
      result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _config.clientId,
          _config.redirectUri,
          serviceConfiguration: _service,
          scopes: const ['openid', 'email', 'profile'],
          additionalParameters:
              preferGoogle ? const {'identity_provider': 'Google'} : null,
        ),
      );
    } catch (e) {
      // Includes the farmer simply backing out of the browser, which is not an
      // error worth a stack trace — the screen shows one message either way.
      throw AuthFailure('$e');
    }

    final idToken = result.idToken;
    final sub = idToken == null ? null : _claim(idToken, 'sub') as String?;
    if (sub == null) {
      // Without a sub there is no partition key, so there is nothing to attach
      // the farmer's records to. Failing loudly beats storing a session that
      // cannot sync.
      throw const AuthFailure('sign-in returned no account identifier');
    }

    final method = _methodFrom(idToken!);
    await _persist(result, sub: sub, method: method);
    return AuthSession(accountId: sub, method: method);
  }

  @override
  Future<String?> accessToken() async {
    final token = await _storage.read(key: _kAccessToken);
    final expiryText = await _storage.read(key: _kAccessExpiry);
    final expiry = expiryText == null ? null : DateTime.tryParse(expiryText);

    // A minute of slack, so a token that expires mid-request is refreshed before
    // it is used rather than after it has already been rejected.
    final fresh = expiry != null &&
        expiry.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 1)));
    if (token != null && fresh) return token;

    final refresh = await _storage.read(key: _kRefreshToken);
    if (refresh == null) return null;

    try {
      final result = await _appAuth.token(
        TokenRequest(
          _config.clientId,
          _config.redirectUri,
          serviceConfiguration: _service,
          refreshToken: refresh,
          grantType: 'refresh_token',
        ),
      );
      await _persistTokens(result);
      return result.accessToken;
    } catch (_) {
      // Offline, or Cognito is down. The session stays exactly as it was: the
      // sync worker treats a null token as a reason to wait, and FR-065 forbids
      // turning a lost connection into a lost session.
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    for (final key in const [
      _kRefreshToken,
      _kAccessToken,
      _kAccessExpiry,
      _kSub,
      _kMethod,
    ]) {
      await _storage.delete(key: key);
    }
  }

  Future<void> _persist(
    AuthorizationTokenResponse result, {
    required String sub,
    required SignInMethod method,
  }) async {
    await _storage.write(key: _kSub, value: sub);
    await _storage.write(key: _kMethod, value: method.name);
    await _persistTokens(result);
  }

  Future<void> _persistTokens(TokenResponse result) async {
    final access = result.accessToken;
    if (access != null) await _storage.write(key: _kAccessToken, value: access);

    final expiry = result.accessTokenExpirationDateTime;
    if (expiry != null) {
      await _storage.write(
          key: _kAccessExpiry, value: expiry.toUtc().toIso8601String());
    }

    // Cognito omits the refresh token on a refresh response. Writing null would
    // erase the only thing keeping a year-long session alive, so an absent value
    // leaves what is already stored untouched.
    final refresh = result.refreshToken;
    if (refresh != null) {
      await _storage.write(key: _kRefreshToken, value: refresh);
    }
  }

  /// Which provider the farmer came through, read from the id token.
  ///
  /// Cognito records a federated sign-in under `identities`; its absence means
  /// the account is native to the pool, which is email and password.
  static SignInMethod _methodFrom(String idToken) {
    final identities = _claim(idToken, 'identities');
    return identities == null ? SignInMethod.email : SignInMethod.google;
  }

  /// Reads one claim out of a JWT **without verifying it**.
  ///
  /// Safe here, and only here: this value decides which local rows belong to this
  /// farmer on this device. Nothing server-side trusts it. The API derives the
  /// owning account from the token's verified `sub` and refuses any account named
  /// in a request body (FR-062, contracts/sync-protocol.md I5), so a forged token
  /// buys an attacker nothing beyond mislabelling records on a phone they already
  /// hold.
  static Object? _claim(String jwt, String name) {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      return (jsonDecode(payload) as Map<String, dynamic>)[name];
    } catch (_) {
      return null;
    }
  }
}
