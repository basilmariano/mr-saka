import '../model/calendar_date.dart';

/// Date derivations. FR-009, FR-017.
abstract final class DateCalc {
  /// FR-017: a step's due date is the planting date plus its days after planting.
  static CalendarDate applicationDueDate({
    required CalendarDate plantingDate,
    required int daysAfterPlanting,
  }) =>
      plantingDate.addDays(daysAfterPlanting);

  /// FR-009: expected harvest date is the planting date plus the variety's typical
  /// maturity in days.
  ///
  /// Returns null when the variety has no recorded maturity — the spec's edge case
  /// "Variety with unknown maturity" requires the farmer be asked for the date rather
  /// than the app inventing one.
  static CalendarDate? expectedHarvestDate({
    required CalendarDate plantingDate,
    required int? maturityDays,
  }) {
    if (maturityDays == null) return null;
    return plantingDate.addDays(maturityDays);
  }

  /// Days elapsed since planting, for the home screen (FR-044).
  static int daysSincePlanting({
    required CalendarDate plantingDate,
    required CalendarDate today,
  }) =>
      plantingDate.daysUntil(today);
}
