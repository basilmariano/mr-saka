import '../model/centavos.dart';
import '../model/square_metres.dart';

/// Why an input is rejected. Each maps to a localised message (FR-056); behaviour
/// never branches on the message text (FR-057).
enum ValidationFailure {
  fieldNameBlank,
  fieldAreaNotPositive,
  expenseAmountNotPositive,
  pricePerKgNotPositive,
  buyerBlank,
  maturityDaysNotPositive,
  ratePerHectareNotPositive,
}

abstract final class Validation {
  /// FR-001, FR-002.
  static List<ValidationFailure> field({
    required String name,
    required SquareMetres area,
  }) {
    final failures = <ValidationFailure>[];
    if (name.trim().isEmpty) failures.add(ValidationFailure.fieldNameBlank);
    // FR-002: reject an area that is "zero, negative, or non-numeric". Non-numeric is
    // caught earlier, when the text fails to parse.
    if (!area.isValid) failures.add(ValidationFailure.fieldAreaNotPositive);
    return failures;
  }

  /// FR-027. Note what is deliberately NOT validated: the date.
  ///
  /// An expense may precede the planting date (land preparation) and may follow the
  /// harvest date (threshing, drying, hauling). FR-031a and the spec edge case
  /// "Expenses before planting" require both be accepted without warning, because
  /// both are normal practice.
  static List<ValidationFailure> expense({required Centavos amount}) =>
      amount.isPositive ? const [] : [ValidationFailure.expenseAmountNotPositive];

  /// FR-034.
  static List<ValidationFailure> sale({
    required Centavos pricePerKg,
    required String buyer,
  }) {
    final failures = <ValidationFailure>[];
    if (!pricePerKg.isPositive) {
      failures.add(ValidationFailure.pricePerKgNotPositive);
    }
    if (buyer.trim().isEmpty) failures.add(ValidationFailure.buyerBlank);
    return failures;
  }

  /// FR-010: a custom variety's maturity, when supplied, must be positive.
  static List<ValidationFailure> variety({required int? maturityDays}) =>
      (maturityDays != null && maturityDays <= 0)
          ? [ValidationFailure.maturityDaysNotPositive]
          : const [];
}
