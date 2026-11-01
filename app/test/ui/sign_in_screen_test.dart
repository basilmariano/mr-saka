import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:saka/data/local/database.dart';
import 'package:saka/data/remote/app_config.dart';
import 'package:saka/ui/account/sign_in_screen.dart';
import 'package:saka/ui/common/app.dart';
import 'package:saka/ui/common/providers.dart';

/// FR-058, and the trap underneath it.
///
/// The fallback [LocalAuthSessionProvider] fabricates an account id and a token.
/// That is correct for tests and for a guest-only build — and catastrophic if the
/// sign-in screen lets a farmer reach it: they would be told they had an account,
/// the guest banner would disappear, and nothing would ever leave the phone. The
/// screen therefore has to know whether this build can really sign anyone in, and
/// say so when it cannot.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const configured = AppConfig(
    apiBaseUrl: 'https://api.example.test/dev',
    region: 'ap-southeast-1',
    userPoolId: 'ap-southeast-1_abc123',
    clientId: 'client-abc',
    hostedUiDomain: 'saka-dev-login.auth.ap-southeast-1.amazoncognito.com',
    redirectUri: 'ph.saka.saka://callback',
  );

  late SakaDatabase db;

  setUp(() => db = SakaDatabase.memory());
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, {AppConfig? config}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        appConfigProvider.overrideWithValue(config),
        clockProvider.overrideWithValue(() => DateTime(2026, 3, 1)),
      ],
      child: const SakaApp(home: SignInScreen()),
    ));
    await tester.pumpAndSettle();
  }

  /// Every FButton on screen, so a test can assert on what is actually pressable
  /// rather than on what merely looks like a button.
  Iterable<FButton> buttonsIn(WidgetTester tester) =>
      tester.widgetList<FButton>(find.byType(FButton));

  testWidgets('an unconfigured build says so and offers no sign-in',
      (tester) async {
    await pump(tester);

    expect(find.byKey(const Key('sign-in-unavailable')), findsOneWidget);

    // Both sign-in buttons disabled; only "continue without an account" works.
    final enabled = buttonsIn(tester).where((b) => b.onPress != null);
    expect(enabled, hasLength(1),
        reason: 'an unconfigured build offered a sign-in button, which the stub '
            'provider would answer as if it had succeeded');
  });

  testWidgets('a configured build offers both routes to the hosted page',
      (tester) async {
    await pump(tester, config: configured);

    expect(find.byKey(const Key('sign-in-unavailable')), findsNothing);

    // Google, email/password, and continue-as-guest.
    final enabled = buttonsIn(tester).where((b) => b.onPress != null);
    expect(enabled, hasLength(3));
  });

  testWidgets('no password is ever typed into this app', (tester) async {
    // The credentials belong on Cognito's page. A field here would be a field
    // whose contents the hosted flow cannot use, and a password this app would
    // then be holding for no reason.
    await pump(tester, config: configured);
    expect(find.byType(FTextField), findsNothing);
  });

  testWidgets('a guest can always continue without an account', (tester) async {
    // FR-017/SC-017: recording a first field must never require an account, so
    // this route stays open even when sign-in is unavailable.
    for (final config in [null, configured]) {
      await pump(tester, config: config);
      final guest = find.text('Continue without an account');
      expect(guest, findsOneWidget);
    }
  });
}
