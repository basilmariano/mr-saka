import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../data/remote/auth_session.dart';
import '../../l10n/app_localizations.dart';
import '../common/providers.dart';
import '../common/widgets/button_label.dart';

/// Sign in or create an account. FR-058, FR-066.
///
/// Both buttons open the same Cognito hosted page in the system browser
/// (research.md R4). Google is offered first because every Android phone is
/// already signed into a Google account — two taps, nothing to remember, and
/// account recovery handled by Google. The other button lands on the same page
/// without the chooser, where email and password, creating an account, and the
/// forgotten-password route (FR-066) all live.
///
/// **This screen deliberately collects no password.** The credentials are typed
/// on the provider's own page, so the app never holds one and no bug here can
/// leak one.
///
/// Signing up carries everything the farmer entered as a guest with them
/// (FR-061), which is why the screen never warns about losing anything.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<AuthSession> Function() action) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() {
        _busy = false;
        _error = l10n.accountSignInFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;
    final accounts = ref.read(accountRepositoryProvider);

    // A build with no backend configured has no account to sign in to. Saying so
    // beats offering buttons that would appear to work: the fallback provider is
    // an in-memory stub, and letting it answer here would tell a farmer their
    // records were backed up when nothing had left the phone.
    final available = ref.watch(signInAvailableProvider);

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.accountSignIn),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).pop(false)),
        ],
      ),
      child: ListView(
        children: [
          Text(l10n.guestBannerBody, style: theme.typography.sm),
          if (!available) ...[
            const SizedBox(height: 16),
            FAlert(
              key: const Key('sign-in-unavailable'),
              icon: const Icon(FIcons.cloudOff),
              title: Text(l10n.accountUnavailable),
            ),
          ],
          const SizedBox(height: 24),
          FButton(
            prefix: const Icon(FIcons.circleUser),
            onPress: (_busy || !available)
                ? null
                : () => _run(() => accounts.signIn(preferGoogle: true)),
            child: ButtonLabel(l10n.accountWithGoogle),
          ),
          const SizedBox(height: 12),
          FButton(
            style: FButtonStyle.outline(),
            onPress:
                (_busy || !available) ? null : () => _run(() => accounts.signIn()),
            child: ButtonLabel(l10n.accountWithEmail),
          ),
          if (available) ...[
            const SizedBox(height: 12),
            Text(l10n.accountOpensBrowser, style: theme.typography.sm),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            FAlert(
              key: const Key('sign-in-error'),
              icon: const Icon(FIcons.circleAlert),
              title: Text(_error!),
            ),
          ],
          const SizedBox(height: 24),
          FButton(
            style: FButtonStyle.ghost(),
            onPress: () => Navigator.of(context).pop(false),
            child: ButtonLabel(l10n.accountContinueAsGuest),
          ),
        ],
      ),
    );
  }
}
