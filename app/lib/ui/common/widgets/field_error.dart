import 'package:flutter/widgets.dart';

/// Pairs a field's error message with the widget state that makes it visible.
///
/// Forui renders a field's `error` widget only when that field carries
/// `WidgetState.error` (see FLabel). Setting the text alone shows nothing, which is
/// a silent failure: validation would run, the farmer would see no message, and the
/// form would simply appear not to respond. Bundling the two here means they cannot
/// drift apart.
class FieldError {
  final states = WidgetStatesController();
  String? _message;

  String? get message => _message;

  /// The widget to pass to a Forui field's `error` slot.
  Widget? get widget => _message == null ? null : Text(_message!);

  void set(String? message) {
    _message = message;
    states.update(WidgetState.error, message != null);
  }

  void clear() => set(null);

  void dispose() => states.dispose();
}
