import '../model/calendar_date.dart';
import '../model/enums.dart';

/// The cropping status state machine. FR-011, FR-011a, FR-011b, FR-011c, FR-012b.
abstract final class CroppingStatusRules {
  /// FR-011a: a cropping moves from planted to growing at whichever comes first —
  /// the first fertilizer application marked done, or this many days after planting.
  ///
  /// The day fallback exists so a cropping never sits in `planted` for a whole season
  /// just because the farmer skipped the basal application.
  static const int growingFallbackDays = 10;

  /// Derives whether a cropping should have advanced from planted to growing.
  ///
  /// FR-011b: this is a date comparison and a boolean, evaluated entirely on the
  /// device. It must never require a network call, or a cropping would fail to
  /// advance while the farmer is in the field with no signal.
  static bool shouldBeGrowing({
    required CalendarDate plantingDate,
    required CalendarDate today,
    required bool anyApplicationDone,
  }) {
    if (anyApplicationDone) return true;
    return plantingDate.daysUntil(today) >= growingFallbackDays;
  }

  /// The status a cropping should hold, given its recorded facts.
  ///
  /// FR-011c: a cropping recorded with a planting date already more than 10 days past
  /// starts in growing rather than briefly claiming to be newly planted.
  ///
  /// FR-012b: harvested and closed are never derived — they are set deliberately, by
  /// recording a harvest and by the farmer closing the cropping. This function only
  /// ever moves planted to growing.
  static CroppingStatus derive({
    required CroppingStatus current,
    required CalendarDate plantingDate,
    required CalendarDate today,
    required bool anyApplicationDone,
  }) {
    if (current != CroppingStatus.planted) return current;
    return shouldBeGrowing(
      plantingDate: plantingDate,
      today: today,
      anyApplicationDone: anyApplicationDone,
    )
        ? CroppingStatus.growing
        : CroppingStatus.planted;
  }

  /// The status a newly started cropping takes. FR-011c.
  static CroppingStatus initialStatus({
    required CalendarDate plantingDate,
    required CalendarDate today,
  }) =>
      derive(
        current: CroppingStatus.planted,
        plantingDate: plantingDate,
        today: today,
        anyApplicationDone: false,
      );

  /// FR-013: a closed cropping rejects new expenses, sales, and schedule changes.
  static bool acceptsRecords(CroppingStatus status) => status.acceptsRecords;

  /// FR-012b: closing is the farmer's declaration that no further costs or sales are
  /// expected. It is never triggered by harvest, by a date, or by the remaining
  /// quantity reaching zero — so there is deliberately no `shouldClose` here.
  static bool canClose(CroppingStatus status) => status == CroppingStatus.harvested;

  static bool canReopen(CroppingStatus status) => status == CroppingStatus.closed;
}
