import 'package:flutter/widgets.dart';

/// A label for an [FButton] that shrinks instead of overflowing.
///
/// FButton lays its child out at its natural size inside its own Row, so a label
/// wider than the button overflows rather than ellipsising — it does not clip or
/// shrink on its own. Wrapping the text in a Flexible makes it a flex child of
/// that Row, which bounds it.
///
/// This matters more than it looks: v1 ships English, but phase 2 adds a local
/// language whose strings are generally longer. A label that just fits today
/// would break the layout on translation, somewhere nobody is looking.
class ButtonLabel extends StatelessWidget {
  const ButtonLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      );
}
