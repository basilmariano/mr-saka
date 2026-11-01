import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// An empty state that invites an action rather than showing a blank section.
///
/// US3 acceptance scenario 4 requires this on the home screen specifically; the same
/// treatment is used wherever a list can legitimately be empty.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.icon = FIcons.sprout,
    super.key,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    // Scrollable rather than a bare Column: an empty state is laid out in
    // whatever space is left, and that can be very little — during a navigation
    // transition, or on a short screen. A Column there overflows; this degrades
    // to a scroll instead.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colors.primary),
            const SizedBox(height: 16),
            Text(title, style: theme.typography.xl2, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.typography.sm.copyWith(color: theme.colors.mutedForeground),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FButton(onPress: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
