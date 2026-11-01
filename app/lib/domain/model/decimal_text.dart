/// Exact decimal <-> scaled-integer conversion.
///
/// SC-009 commits that every figure the app reports matches the farmer's own hand
/// calculation. Binary floating point cannot represent 0.1 exactly, so parsing user
/// input through `double.parse` and summing it drifts: a season of peso amounts will
/// eventually disagree with the farmer's calculator by a centavo, and the farmer is
/// right. Every quantity in this app is therefore stored as a scaled integer, and the
/// only conversion between text and integer happens here.
///
/// See research.md R5.
library;

/// Thrown when text cannot be read as a decimal number.
class DecimalFormatException implements Exception {
  const DecimalFormatException(this.input, this.reason);
  final String input;
  final String reason;
  @override
  String toString() => 'DecimalFormatException("$input"): $reason';
}

/// Integer division rounded half-up, correct for negative operands.
///
/// Used only at the display boundary. No intermediate domain result is ever rounded
/// (data-model.md, Rounding rule).
int roundedDiv(int numerator, int denominator) {
  if (denominator == 0) {
    throw ArgumentError('roundedDiv: denominator must not be zero');
  }
  final negative = (numerator < 0) != (denominator < 0);
  final a = numerator.abs();
  final b = denominator.abs();
  final quotient = (2 * a + b) ~/ (2 * b);
  return negative ? -quotient : quotient;
}

/// Parses decimal [text] into an integer scaled by 10^[decimals].
///
/// `parseScaled('2.5', 4)` is `25000` — 2.5 hectares as square metres.
/// Digits beyond [decimals] are rejected rather than silently truncated, because
/// quietly dropping a centavo is exactly the failure SC-009 forbids.
int parseScaled(String text, int decimals) {
  final trimmed = text.trim().replaceAll(',', '');
  if (trimmed.isEmpty) {
    throw DecimalFormatException(text, 'empty');
  }
  final match = RegExp(r'^(-)?(\d*)(?:\.(\d*))?$').firstMatch(trimmed);
  if (match == null) {
    throw DecimalFormatException(text, 'not a decimal number');
  }
  final negative = match.group(1) != null;
  final whole = match.group(2) ?? '';
  final fraction = match.group(3) ?? '';
  if (whole.isEmpty && fraction.isEmpty) {
    throw DecimalFormatException(text, 'no digits');
  }
  if (fraction.length > decimals) {
    throw DecimalFormatException(
      text,
      'more than $decimals decimal place(s); refusing to silently truncate',
    );
  }
  final padded = fraction.padRight(decimals, '0');
  final digits = '${whole.isEmpty ? '0' : whole}$padded';
  final value = int.tryParse(digits);
  if (value == null) {
    throw DecimalFormatException(text, 'out of range');
  }
  return negative ? -value : value;
}

/// Formats a scaled integer back to text with exactly [decimals] places.
String formatScaled(int scaled, int decimals) {
  if (decimals == 0) return scaled.toString();
  final negative = scaled < 0;
  final digits = scaled.abs().toString().padLeft(decimals + 1, '0');
  final cut = digits.length - decimals;
  final text = '${digits.substring(0, cut)}.${digits.substring(cut)}';
  return negative ? '-$text' : text;
}

/// Rescales [scaled] from [fromDecimals] to [toDecimals], rounding half-up when
/// precision is lost.
int rescale(int scaled, int fromDecimals, int toDecimals) {
  if (toDecimals == fromDecimals) return scaled;
  if (toDecimals > fromDecimals) {
    var result = scaled;
    for (var i = 0; i < toDecimals - fromDecimals; i++) {
      result *= 10;
    }
    return result;
  }
  var divisor = 1;
  for (var i = 0; i < fromDecimals - toDecimals; i++) {
    divisor *= 10;
  }
  return roundedDiv(scaled, divisor);
}

/// Inserts thousands separators into the whole part of formatted decimal [text].
String withThousandsSeparators(String text) {
  final negative = text.startsWith('-');
  final body = negative ? text.substring(1) : text;
  final dot = body.indexOf('.');
  final whole = dot == -1 ? body : body.substring(0, dot);
  final rest = dot == -1 ? '' : body.substring(dot);
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return '${negative ? '-' : ''}$buffer$rest';
}
