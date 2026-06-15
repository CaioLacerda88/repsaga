import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/workouts/utils/cardio_format.dart';

void main() {
  group('CardioFormat.duration (mm:ss)', () {
    test('formats whole minutes with zero-padded seconds', () {
      expect(CardioFormat.duration(1800), '30:00');
      expect(CardioFormat.duration(1725), '28:45');
      expect(CardioFormat.duration(485), '8:05');
    });

    test('does NOT wrap into hours — 95-minute ride stays mm:ss', () {
      expect(CardioFormat.duration(95 * 60), '95:00');
    });

    test('clamps negative input to 0:00 (defensive)', () {
      expect(CardioFormat.duration(-30), '0:00');
    });
  });

  group('CardioFormat.parseDuration', () {
    test('parses mm:ss', () {
      expect(CardioFormat.parseDuration('28:45'), 1725);
      expect(CardioFormat.parseDuration(' 8:05 '), 485);
    });

    test('parses bare minutes', () {
      expect(CardioFormat.parseDuration('28'), 1680);
      expect(CardioFormat.parseDuration('0'), 0);
    });

    test('rejects malformed / out-of-range input', () {
      expect(CardioFormat.parseDuration(''), isNull);
      expect(CardioFormat.parseDuration('abc'), isNull);
      expect(CardioFormat.parseDuration('28:75'), isNull, reason: 'ss >= 60');
      expect(CardioFormat.parseDuration('28:45:10'), isNull);
      expect(CardioFormat.parseDuration('-5'), isNull);
      expect(CardioFormat.parseDuration('-5:00'), isNull);
    });
  });

  group('CardioFormat distance unit + conversion', () {
    test('display unit derives from the profile weight unit', () {
      expect(CardioFormat.distanceUnitFor('kg'), 'km');
      expect(CardioFormat.distanceUnitFor('lbs'), 'mi');
    });

    test('meters ↔ km round-trip', () {
      expect(CardioFormat.metersToDisplay(5200, 'km'), 5.2);
      expect(CardioFormat.displayToMeters(5.2, 'km'), 5200.0);
    });

    test('meters ↔ mi uses the international mile', () {
      expect(CardioFormat.displayToMeters(1.0, 'mi'), 1609.344);
      expect(CardioFormat.metersToDisplay(1609.344, 'mi'), 1.0);
    });
  });

  group('CardioFormat.distanceValue (locale-aware display)', () {
    test('en renders a dot decimal', () {
      expect(
        CardioFormat.distanceValue(5200, distanceUnit: 'km', locale: 'en'),
        '5.2',
      );
    });

    test('pt renders a comma decimal', () {
      expect(
        CardioFormat.distanceValue(5200, distanceUnit: 'km', locale: 'pt'),
        '5,2',
      );
    });

    test('whole-number distances render without a decimal', () {
      expect(
        CardioFormat.distanceValue(5000, distanceUnit: 'km', locale: 'pt'),
        '5',
      );
    });
  });

  group('CardioFormat.parseDistanceToMeters', () {
    test('accepts dot AND comma decimal separators (pt-BR keyboard habit)', () {
      expect(CardioFormat.parseDistanceToMeters('5.2', 'km'), 5200.0);
      expect(CardioFormat.parseDistanceToMeters('5,2', 'km'), 5200.0);
    });

    test('converts display miles back to canonical meters', () {
      expect(
        CardioFormat.parseDistanceToMeters('2', 'mi'),
        closeTo(3218.688, 1e-9),
      );
    });

    test('rejects empty / negative / non-numeric input', () {
      expect(CardioFormat.parseDistanceToMeters('', 'km'), isNull);
      expect(CardioFormat.parseDistanceToMeters('  ', 'km'), isNull);
      expect(CardioFormat.parseDistanceToMeters('-1', 'km'), isNull);
      expect(CardioFormat.parseDistanceToMeters('abc', 'km'), isNull);
    });
  });
}
