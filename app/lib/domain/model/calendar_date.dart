/// A calendar date with no time component.
///
/// spec Assumptions: "Dates are calendar dates in the farmer's local time; no
/// time-of-day precision is needed anywhere in the feature." Carrying a `DateTime`
/// around invites time-zone arithmetic into due dates and harvest dates, where an
/// hour's drift can move a date by a day.
class CalendarDate implements Comparable<CalendarDate> {
  const CalendarDate(this.year, this.month, this.day);

  factory CalendarDate.fromDateTime(DateTime dateTime) =>
      CalendarDate(dateTime.year, dateTime.month, dateTime.day);

  /// Parses `"2026-03-01"`.
  factory CalendarDate.parseIso(String text) {
    final parts = text.split('-');
    if (parts.length != 3) {
      throw FormatException('Not an ISO calendar date', text);
    }
    return CalendarDate(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  final int year;
  final int month;
  final int day;

  DateTime toDateTime() => DateTime(year, month, day);

  /// FR-009, FR-017: expected harvest and due dates are a plain day offset.
  CalendarDate addDays(int days) =>
      CalendarDate.fromDateTime(DateTime(year, month, day + days));

  /// Whole days from this date to [other]; negative when [other] is earlier.
  int daysUntil(CalendarDate other) =>
      other.toDateTime().difference(toDateTime()).inDays;

  bool isBefore(CalendarDate other) => compareTo(other) < 0;
  bool isAfter(CalendarDate other) => compareTo(other) > 0;

  String toIso() => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(CalendarDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}
