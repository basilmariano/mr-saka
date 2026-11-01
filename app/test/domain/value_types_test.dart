import 'package:saka/domain/model/calendar_date.dart';
import 'package:saka/domain/model/centavos.dart';
import 'package:saka/domain/model/decimal_text.dart';
import 'package:saka/domain/model/grams.dart';
import 'package:saka/domain/model/square_metres.dart';
import 'package:test/test.dart';

void main() {
  group('roundedDiv is half-up and sign-correct', () {
    test('rounds halves up', () {
      expect(roundedDiv(5, 2), 3);
      expect(roundedDiv(3, 2), 2);
      expect(roundedDiv(4, 2), 2);
    });

    test('rounds negative halves away from zero', () {
      expect(roundedDiv(-5, 2), -3);
      expect(roundedDiv(5, -2), -3);
    });

    test('rejects a zero denominator rather than returning infinity', () {
      expect(() => roundedDiv(1, 0), throwsArgumentError);
    });
  });

  group('parseScaled keeps farmer input exact', () {
    test('parses whole and fractional pesos', () {
      expect(parseScaled('3500', 2), 350000);
      expect(parseScaled('3500.50', 2), 350050);
      expect(parseScaled('3,500.05', 2), 350005);
      expect(parseScaled('.5', 2), 50);
    });

    test('refuses to silently truncate excess precision', () {
      // Quietly dropping a centavo is exactly the failure SC-009 forbids.
      expect(() => parseScaled('1.005', 2), throwsA(isA<DecimalFormatException>()));
    });

    test('rejects junk', () {
      expect(() => parseScaled('abc', 2), throwsA(isA<DecimalFormatException>()));
      expect(() => parseScaled('', 2), throwsA(isA<DecimalFormatException>()));
    });
  });

  group('Centavos', () {
    test('sums a season of expenses without drift', () {
      // The classic floating point failure: 0.1 + 0.2 != 0.3 as doubles.
      final amounts = List.generate(1000, (_) => Centavos.parse('0.10'));
      expect(Centavos.sum(amounts), Centavos.parse('100.00'));
    });

    test('formats with thousands separators', () {
      expect(Centavos.parse('23500').format(), '23,500.00');
      expect(Centavos.parse('-1234.5').format(), '-1,234.50');
    });

    test('computes category share to one decimal place', () {
      // FR-030: each category's amount and its share of the overall total.
      final part = Centavos.fromPesos(3500);
      final whole = Centavos.fromPesos(23500);
      expect(part.percentOfScaled1(whole), 149); // 14.9%
    });

    test('share of a zero total is zero, not a division error', () {
      expect(Centavos.fromPesos(10).percentOfScaled1(Centavos.zero), 0);
    });
  });

  group('Grams', () {
    test('converts to tons for yield display', () {
      // quickstart Scenario 1: 100 sacks x 50 kg = 5,000 kg = 5.00 tons.
      expect(Grams.fromKg(5000).formatTons(), '5.00');
    });

    test('converts to 50 kg bags with one decimal place', () {
      // FR-016: a farmer buying fertilizer needs to see 5.5 bags, not a rounded 6.
      expect(Grams.fromKg(250).formatBags(), '5.0');
      expect(Grams.fromKg(275).formatBags(), '5.5');
      expect(Grams.fromKg(50).formatBags(), '1.0');
    });

    test('parses a non-whole average kg per sack exactly', () {
      // FR-032 allows an average kg per sack that is not a whole number.
      expect(Grams.parseKg('50.5').value, 50500);
    });
  });

  group('SquareMetres', () {
    test('parses hectares exactly', () {
      expect(SquareMetres.parseHectares('2.5').value, 25000);
      expect(SquareMetres.parseHectares('1').value, 10000);
    });

    test('rejects zero and negative areas', () {
      // FR-002: reject an area that is "zero, negative, or non-numeric".
      expect(SquareMetres.parseHectares('0').isValid, isFalse);
      expect(SquareMetres.parseHectares('-1').isValid, isFalse);
      expect(() => SquareMetres.parseHectares('abc'),
          throwsA(isA<DecimalFormatException>()));
    });

    test('formats hectares for display', () {
      expect(SquareMetres.parseHectares('2.5').formatHectares(), '2.50');
    });
  });

  group('CalendarDate', () {
    test('adds days across a month boundary', () {
      // FR-017: a step 14 days after planting on 1 March is due 15 March.
      expect(const CalendarDate(2026, 3, 1).addDays(14), const CalendarDate(2026, 3, 15));
      expect(const CalendarDate(2026, 2, 20).addDays(10), const CalendarDate(2026, 3, 2));
    });

    test('handles a leap year', () {
      expect(const CalendarDate(2028, 2, 28).addDays(1), const CalendarDate(2028, 2, 29));
    });

    test('counts days between dates', () {
      expect(const CalendarDate(2026, 3, 1).daysUntil(const CalendarDate(2026, 3, 11)), 10);
      expect(const CalendarDate(2026, 3, 11).daysUntil(const CalendarDate(2026, 3, 1)), -10);
    });

    test('round-trips ISO text', () {
      expect(CalendarDate.parseIso('2026-03-01').toIso(), '2026-03-01');
    });
  });
}
