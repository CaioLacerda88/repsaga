import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/xp_distribution.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';

Map<String, dynamic> _loadFixtures() {
  final file = File('test/fixtures/rpg_xp_fixtures.json');
  return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
}

const double _eps = 1e-9;

void main() {
  group('Attribution.fromMap — validation', () {
    test('accepts a valid map summing to 1.0', () {
      final attr = Attribution.fromMap({
        'chest': 0.7,
        'shoulders': 0.2,
        'arms': 0.1,
      });
      expect(attr.shares[BodyPart.chest], 0.7);
      expect(attr.shares[BodyPart.shoulders], 0.2);
      expect(attr.shares[BodyPart.arms], 0.1);
      expect(attr.sum, closeTo(1.0, _eps));
    });

    test('accepts sum within ±0.01 tolerance (e.g. 0.99 or 1.01)', () {
      expect(
        () => Attribution.fromMap({'chest': 0.55, 'arms': 0.45}),
        returnsNormally,
      );
      expect(
        () => Attribution.fromMap({'chest': 0.6, 'arms': 0.4}),
        returnsNormally,
      );
      // 0.99 is exactly at the tolerance boundary.
      expect(
        () => Attribution.fromMap({'chest': 0.59, 'arms': 0.40}),
        returnsNormally,
      );
    });

    test('rejects sum > 1.01', () {
      expect(
        () => Attribution.fromMap({'chest': 0.7, 'shoulders': 0.4}),
        throwsArgumentError,
      );
    });

    test('rejects sum < 0.99', () {
      expect(
        () => Attribution.fromMap({'chest': 0.3, 'arms': 0.3}),
        throwsArgumentError,
      );
    });

    test('rejects unknown body-part keys', () {
      expect(
        () => Attribution.fromMap({'chest': 0.5, 'mystery_muscle': 0.5}),
        throwsArgumentError,
      );
    });

    test('rejects negative shares', () {
      expect(
        () => Attribution.fromMap({'chest': -0.1, 'arms': 1.1}),
        throwsArgumentError,
      );
    });

    test('rejects NaN / Infinity', () {
      expect(
        () => Attribution.fromMap({'chest': double.nan, 'arms': 1.0}),
        throwsArgumentError,
      );
      expect(
        () => Attribution.fromMap({'chest': double.infinity}),
        throwsArgumentError,
      );
    });

    test('rejects empty map', () {
      expect(() => Attribution.fromMap({}), throwsArgumentError);
    });

    test('cardio key is accepted in v1 (forward compat)', () {
      // v1 doesn't earn from cardio, but the schema accepts cardio rows.
      // The model must round-trip the value without error.
      final attr = Attribution.fromMap({'cardio': 1.0});
      expect(attr.shares[BodyPart.cardio], 1.0);
    });
  });

  group('Attribution.fromPrimaryMuscle — NULL fallback', () {
    test('builds a 1.0 share to the primary muscle', () {
      final attr = Attribution.fromPrimaryMuscle(BodyPart.legs);
      expect(attr.shares.length, 1);
      expect(attr.shares[BodyPart.legs], 1.0);
      expect(attr.sum, 1.0);
    });

    test('cardio primary works (v2 forward compat)', () {
      final attr = Attribution.fromPrimaryMuscle(BodyPart.cardio);
      expect(attr.shares[BodyPart.cardio], 1.0);
    });
  });

  group('Attribution.toJson + equality', () {
    test('toJson produces dbValue-keyed map', () {
      final attr = Attribution.fromMap({
        'chest': 0.7,
        'shoulders': 0.2,
        'arms': 0.1,
      });
      expect(attr.toJson(), {'chest': 0.7, 'shoulders': 0.2, 'arms': 0.1});
    });

    test('equality compares share-for-share', () {
      final a = Attribution.fromMap({'chest': 0.7, 'arms': 0.3});
      final b = Attribution.fromMap({'arms': 0.3, 'chest': 0.7});
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('XpDistribution.distribute', () {
    test('parity with Python sim — every default exercise', () {
      final fixtures = _loadFixtures();
      final cases = fixtures['attribution_distribution'] as List<dynamic>;
      for (final raw in cases) {
        final c = raw as Map<String, dynamic>;
        final attrMap = (c['attribution'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, v as num),
        );
        final attr = Attribution.fromMap(attrMap);
        final setXp = (c['set_xp_input'] as num).toDouble();
        final expected = (c['expected_distribution'] as Map<String, dynamic>)
            .map(
              (k, v) =>
                  MapEntry(BodyPart.fromDbValue(k), (v as num).toDouble()),
            );

        final distributed = XpDistribution.distribute(
          setXp: setXp,
          attribution: attr,
        );
        expect(
          distributed.length,
          expected.length,
          reason: '${c['exercise_slug']} distribution length mismatch',
        );
        expected.forEach((bp, xp) {
          expect(
            distributed[bp],
            closeTo(xp, _eps),
            reason: '${c['exercise_slug']} → ${bp.dbValue}',
          );
        });
      }
    });

    test('zero set_xp produces empty map', () {
      final attr = Attribution.fromPrimaryMuscle(BodyPart.legs);
      expect(XpDistribution.distribute(setXp: 0, attribution: attr), isEmpty);
      expect(XpDistribution.distribute(setXp: -5, attribution: attr), isEmpty);
    });

    test('preserves the attribution share count (no zero-share noise)', () {
      // bench_press attribution has 3 shares (chest, shoulders, arms).
      final attr = Attribution.fromMap({
        'chest': 0.70,
        'shoulders': 0.20,
        'arms': 0.10,
      });
      final result = XpDistribution.distribute(setXp: 100, attribution: attr);
      expect(result.length, 3);
      expect(result[BodyPart.chest], closeTo(70.0, _eps));
      expect(result[BodyPart.shoulders], closeTo(20.0, _eps));
      expect(result[BodyPart.arms], closeTo(10.0, _eps));
    });

    test('NULL fallback (primary-muscle) routes 100% to one body part', () {
      final attr = Attribution.fromPrimaryMuscle(BodyPart.back);
      final result = XpDistribution.distribute(setXp: 50, attribution: attr);
      expect(result.length, 1);
      expect(result[BodyPart.back], 50.0);
    });
  });

  group('BodyPart enum', () {
    test('dbValue is the lowercase enum name', () {
      expect(BodyPart.chest.dbValue, 'chest');
      expect(BodyPart.cardio.dbValue, 'cardio');
    });

    test('fromDbValue round-trips every variant', () {
      for (final bp in BodyPart.values) {
        expect(BodyPart.fromDbValue(bp.dbValue), bp);
      }
    });

    test('tryFromDbValue returns null on unknown', () {
      expect(BodyPart.tryFromDbValue('mystery'), isNull);
    });

    test('fromDbValue throws on unknown', () {
      expect(() => BodyPart.fromDbValue('mystery'), throwsArgumentError);
    });

    test('activeBodyParts is the seven tracks incl. cardio (Phase 38e)', () {
      // Phase 38e flip: cardio now contributes to Character Level, so it
      // joins activeBodyParts (appended LAST to preserve strength order).
      expect(activeBodyParts.length, 7);
      expect(activeBodyParts.contains(BodyPart.cardio), isTrue);
      expect(activeBodyParts, [
        BodyPart.chest,
        BodyPart.back,
        BodyPart.legs,
        BodyPart.shoulders,
        BodyPart.arms,
        BodyPart.core,
        BodyPart.cardio,
      ]);
    });

    test('strengthBodyParts is the six strength tracks (cardio excluded)', () {
      // Class resolution / Ascendant spread reads strengthBodyParts, NOT
      // activeBodyParts — cardio is recognised via cardio titles, never a
      // class, so it must never enter the class system.
      expect(strengthBodyParts.length, 6);
      expect(strengthBodyParts.contains(BodyPart.cardio), isFalse);
      expect(strengthBodyParts, [
        BodyPart.chest,
        BodyPart.back,
        BodyPart.legs,
        BodyPart.shoulders,
        BodyPart.arms,
        BodyPart.core,
      ]);
    });
  });
}
