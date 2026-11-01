import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../l10n/app_localizations.dart';
import '../common/providers.dart';
import '../common/widgets/button_label.dart';
import 'sign_in_screen.dart';

/// Tracks whether the guest prompt has already been shown this session.
///
/// FR-067: a guest must not be asked more than once per session, so trialling the
/// app is not obstructed.
final guestPromptDismissedProvider = StateProvider<bool>((ref) => false);

/// Tells a guest, plainly and as a standing fact, that their records are not
/// protected.
///
/// FR-060 requires this be stated plainly. The spec notes it is deliberately a
/// standing notice rather than a one-time dialog: a guest's records really are
/// unprotected, and they should know while they are deciding — not after losing
/// the phone.
class GuestBanner extends ConsumerWidget {
  const GuestBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;
    final isGuest = ref.watch(isGuestProvider).valueOrNull ?? false;
    final dismissed = ref.watch(guestPromptDismissedProvider);

    if (!isGuest || dismissed) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: FCard(
        title: Text(l10n.guestBannerTitle),
        subtitle: Text(l10n.guestBannerBody, style: theme.typography.sm),
        // Both buttons share the width rather than sizing to their labels: two
        // min-width buttons overflowed a phone-width card, and splitting the row
        // also gives each a bigger tap target for use in the field.
        child: Row(
          children: [
            Expanded(
              child: FButton(
                style: FButtonStyle.ghost(),
                onPress: () =>
                    ref.read(guestPromptDismissedProvider.notifier).state = true,
                child: ButtonLabel(l10n.guestBannerDismiss),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FButton(
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
                ),
                child: ButtonLabel(l10n.guestBannerAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
