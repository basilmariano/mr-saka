import 'package:flutter_test/flutter_test.dart';
import 'package:saka/data/remote/app_config.dart';

/// The all-or-nothing rule that decides whether a farmer is offered an account.
///
/// This matters more than its size suggests. A half-configured build is the one
/// that fails at the OAuth redirect — after the farmer has already typed their
/// password on Cognito's page — rather than at startup where someone would notice
/// it. So "any value missing means no sign-in at all" has to hold for every
/// combination, not just the obvious empty one.
void main() {
  const full = {
    'apiBaseUrl': 'https://api.example.test/dev',
    'userPoolId': 'ap-southeast-1_abc123',
    'clientId': 'client-abc',
    'hostedUiDomain': 'saka-dev-login.auth.ap-southeast-1.amazoncognito.com',
    'redirectUri': 'ph.saka.saka://callback',
  };

  AppConfig? resolve([Map<String, String> overrides = const {}]) {
    final v = {...full, ...overrides};
    return AppConfig.resolve(
      apiBaseUrl: v['apiBaseUrl']!,
      userPoolId: v['userPoolId']!,
      clientId: v['clientId']!,
      hostedUiDomain: v['hostedUiDomain']!,
      redirectUri: v['redirectUri']!,
    );
  }

  test('a complete configuration resolves', () {
    final config = resolve();
    expect(config, isNotNull);
    expect(config!.apiBaseUrl, 'https://api.example.test/dev');
    expect(config.redirectUri, 'ph.saka.saka://callback');
  });

  test('any single missing value means no configuration at all', () {
    for (final key in full.keys) {
      expect(resolve({key: ''}), isNull,
          reason: 'missing $key still produced a config, so the app would offer '
              'sign-in and fail partway through it');
    }
  });

  test('whitespace is not configuration', () {
    // A define left as a placeholder, or a trailing newline from a shell
    // pipeline, must not read as a configured backend.
    for (final key in full.keys) {
      expect(resolve({key: '   '}), isNull, reason: key);
    }
  });

  test('the region is taken from the pool id rather than set separately', () {
    // Two sources for one fact is two things to keep in step. The pool id
    // already carries its region, so a region that disagrees with its pool is
    // not representable.
    expect(resolve()!.region, 'ap-southeast-1');
    expect(resolve({'userPoolId': 'us-east-1_zzz'})!.region, 'us-east-1');
  });

  test('the build-time read is all-or-nothing, however this suite was run', () {
    // Usually null: the fresh-clone case, no --dart-define anywhere, guest-only
    // rather than a crash. But `flutter test --dart-define-from-file=env.json` is
    // a reasonable thing to run, and asserting null outright would fail for the
    // developer who does. The invariant that actually matters is that it is never
    // half-configured, which holds either way.
    final config = AppConfig.fromEnvironment();
    if (config == null) return;
    for (final value in [
      config.apiBaseUrl,
      config.region,
      config.userPoolId,
      config.clientId,
      config.hostedUiDomain,
      config.redirectUri,
    ]) {
      expect(value, isNotEmpty);
    }
  });
}
