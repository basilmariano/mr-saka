/// Which deployed backend this build talks to.
///
/// Every value comes from `terraform -chdir=api/terraform output` and is supplied
/// at build time:
///
/// ```sh
/// flutter run --dart-define-from-file=env.json
/// ```
///
/// None of them is a secret: the API URL is public, the pool id is in every
/// token, and the Cognito client id is deliberately public because a mobile
/// client ships on the handset and can hold no secret — which is also why the
/// OAuth flow is authorization-code + PKCE rather than anything involving a
/// client secret.
///
/// **Absent configuration is a supported state, not an error.** With no defines
/// the app runs guest-only: records stay on the device, the farmer is told so
/// plainly (FR-060, and the sign-in screen refuses to offer an account it cannot
/// create), and nothing crashes. That is what README promises and what a fresh
/// clone does before anyone has deployed anything.
///
/// Build-time defines rather than a bundled `.env`: an asset must exist for the
/// build to succeed at all, so the "runs without configuration" promise would
/// hold only for someone who had already created the file it says is optional.
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.region,
    required this.userPoolId,
    required this.clientId,
    required this.hostedUiDomain,
    required this.redirectUri,
  });

  final String apiBaseUrl;
  final String region;
  final String userPoolId;
  final String clientId;

  /// Host only, no scheme: `saka-dev-login.auth.ap-southeast-1.amazoncognito.com`.
  final String hostedUiDomain;

  /// Must match a `callback_urls` entry on the Cognito app client exactly, and
  /// the scheme the app registers with the OS. A mismatch fails at the redirect,
  /// after the farmer has already typed their password, so it is worth getting
  /// right before shipping rather than discovering in the field.
  final String redirectUri;

  static const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const _userPoolId = String.fromEnvironment('COGNITO_USER_POOL_ID');
  static const _clientId = String.fromEnvironment('COGNITO_CLIENT_ID');
  static const _hostedUiDomain =
      String.fromEnvironment('COGNITO_HOSTED_UI_DOMAIN');
  static const _redirectUri = String.fromEnvironment('OAUTH_REDIRECT_URI');

  /// Null when anything required is missing.
  ///
  /// Null rather than a thrown error or a half-filled object: a partially
  /// configured build is the one that fails at the redirect instead of at
  /// startup, and sign-in that is absent is far easier to diagnose than sign-in
  /// that is present and broken.
  static AppConfig? fromEnvironment() => resolve(
        apiBaseUrl: _apiBaseUrl,
        userPoolId: _userPoolId,
        clientId: _clientId,
        hostedUiDomain: _hostedUiDomain,
        redirectUri: _redirectUri,
      );

  /// The same rule, with the values passed in, so it can be tested.
  ///
  /// `String.fromEnvironment` is a compile-time constant and cannot be varied
  /// from a test, which would otherwise leave the all-or-nothing rule — the part
  /// that decides whether a farmer is offered an account at all — as the only
  /// unverified logic in the sign-in path.
  static AppConfig? resolve({
    required String apiBaseUrl,
    required String userPoolId,
    required String clientId,
    required String hostedUiDomain,
    required String redirectUri,
  }) {
    final values = [
      apiBaseUrl.trim(),
      userPoolId.trim(),
      clientId.trim(),
      hostedUiDomain.trim(),
      redirectUri.trim(),
    ];
    if (values.any((v) => v.isEmpty)) return null;

    return AppConfig(
      apiBaseUrl: values[0],
      // The pool id carries its own region as a prefix, so there is nothing to
      // keep in step and no way for a region setting to drift away from the pool
      // it is supposed to describe.
      region: values[1].split('_').first,
      userPoolId: values[1],
      clientId: values[2],
      hostedUiDomain: values[3],
      redirectUri: values[4],
    );
  }
}
