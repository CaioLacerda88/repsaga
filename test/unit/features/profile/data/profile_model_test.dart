import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/profile/models/profile.dart';

void main() {
  group('Profile model', () {
    test('fromJson creates Profile correctly', () {
      final json = {
        'id': 'user-123',
        'display_name': 'John',
        'fitness_level': 'intermediate',
        'weight_unit': 'kg',
        'created_at': '2026-01-01T00:00:00Z',
      };
      final profile = Profile.fromJson(json);
      expect(profile.id, 'user-123');
      expect(profile.displayName, 'John');
      expect(profile.fitnessLevel, 'intermediate');
      expect(profile.weightUnit, 'kg');
    });

    test('toJson produces correct map', () {
      const profile = Profile(
        id: 'user-123',
        displayName: 'John',
        fitnessLevel: 'beginner',
        weightUnit: 'lbs',
      );
      final json = profile.toJson();
      expect(json['id'], 'user-123');
      expect(json['display_name'], 'John');
      expect(json['fitness_level'], 'beginner');
      expect(json['weight_unit'], 'lbs');
    });

    test('defaults weightUnit to kg', () {
      final profile = Profile.fromJson({'id': 'user-123'});
      expect(profile.weightUnit, 'kg');
    });

    test('copyWith produces new instance', () {
      const profile = Profile(id: 'user-123', weightUnit: 'kg');
      final updated = profile.copyWith(weightUnit: 'lbs');
      expect(updated.weightUnit, 'lbs');
      expect(profile.weightUnit, 'kg');
    });

    test('displayName is null when absent from json', () {
      final profile = Profile.fromJson({'id': 'user-123'});
      expect(profile.displayName, isNull);
    });

    test('fitnessLevel is null when absent from json', () {
      final profile = Profile.fromJson({'id': 'user-123'});
      expect(profile.fitnessLevel, isNull);
    });

    test('two profiles with same fields are equal', () {
      const a = Profile(id: 'user-1', displayName: 'Alice', weightUnit: 'kg');
      const b = Profile(id: 'user-1', displayName: 'Alice', weightUnit: 'kg');
      expect(a, equals(b));
    });

    test('two profiles with different weightUnit are not equal', () {
      const a = Profile(id: 'user-1', weightUnit: 'kg');
      const b = Profile(id: 'user-1', weightUnit: 'lbs');
      expect(a, isNot(equals(b)));
    });

    test('defaults locale to en when not specified', () {
      final profile = Profile.fromJson({'id': 'user-123'});
      expect(profile.locale, 'en');
    });

    test('defaults locale to en when constructed without locale', () {
      const profile = Profile(id: 'user-123');
      expect(profile.locale, 'en');
    });

    test('locale can be set to pt', () {
      const profile = Profile(id: 'user-123', locale: 'pt');
      expect(profile.locale, 'pt');
    });

    test('fromJson parses locale from JSON', () {
      final json = {'id': 'user-123', 'locale': 'pt'};
      final profile = Profile.fromJson(json);
      expect(profile.locale, 'pt');
    });

    test('toJson includes locale field', () {
      const profile = Profile(id: 'user-123', locale: 'pt');
      final json = profile.toJson();
      expect(json['locale'], 'pt');
    });

    test('toJson includes default locale en', () {
      const profile = Profile(id: 'user-123');
      final json = profile.toJson();
      expect(json['locale'], 'en');
    });

    test('copyWith updates locale', () {
      const profile = Profile(id: 'user-123', locale: 'en');
      final updated = profile.copyWith(locale: 'pt');
      expect(updated.locale, 'pt');
      expect(profile.locale, 'en');
    });

    test('parses createdAt datetime correctly', () {
      final json = {'id': 'user-1', 'created_at': '2026-03-15T08:30:00.000Z'};
      final profile = Profile.fromJson(json);
      expect(profile.createdAt, isA<DateTime>());
      expect(profile.createdAt!.year, 2026);
      expect(profile.createdAt!.month, 3);
      expect(profile.createdAt!.day, 15);
    });

    // -----------------------------------------------------------------
    // Phase 24c — bodyweight_kg
    //
    // The user opts into bodyweight tracking via the profile settings or
    // the active-workout lazy prompt. Until they do, the field stays null
    // and the SQL `record_xp` RPC falls back to `COALESCE(bodyweight_kg, 0)`
    // for the effective-load math (entered weight only).
    // -----------------------------------------------------------------
    group('bodyweightKg (Phase 24c)', () {
      test('is null when bodyweight_kg key is absent from JSON', () {
        final profile = Profile.fromJson({'id': 'user-123'});
        expect(profile.bodyweightKg, isNull);
      });

      test('is null when bodyweight_kg is explicitly null in JSON', () {
        final json = {'id': 'user-123', 'bodyweight_kg': null};
        final profile = Profile.fromJson(json);
        expect(profile.bodyweightKg, isNull);
      });

      test('parses double value from JSON', () {
        final json = {'id': 'user-123', 'bodyweight_kg': 70.5};
        final profile = Profile.fromJson(json);
        expect(profile.bodyweightKg, 70.5);
      });

      test('coerces integer JSON value to double', () {
        // Postgres numeric(5,2) can serialize as a bare int via PostgREST
        // when there's no fractional component (e.g. 80 not 80.00).
        final json = {'id': 'user-123', 'bodyweight_kg': 80};
        final profile = Profile.fromJson(json);
        expect(profile.bodyweightKg, 80.0);
      });

      test('toJson includes bodyweight_kg when set', () {
        const profile = Profile(id: 'user-123', bodyweightKg: 72.3);
        final json = profile.toJson();
        expect(json['bodyweight_kg'], 72.3);
      });

      test('toJson serializes null bodyweight_kg as null', () {
        const profile = Profile(id: 'user-123');
        final json = profile.toJson();
        expect(json.containsKey('bodyweight_kg'), isTrue);
        expect(json['bodyweight_kg'], isNull);
      });

      test('toJson round-trip preserves bodyweightKg', () {
        const profile = Profile(id: 'user-123', bodyweightKg: 65.0);
        final roundTripped = Profile.fromJson(profile.toJson());
        expect(roundTripped.bodyweightKg, 65.0);
        expect(roundTripped, profile);
      });

      test('toJson round-trip preserves null bodyweightKg', () {
        const profile = Profile(id: 'user-123');
        final roundTripped = Profile.fromJson(profile.toJson());
        expect(roundTripped.bodyweightKg, isNull);
      });

      test('copyWith updates bodyweightKg', () {
        const profile = Profile(id: 'user-123');
        final updated = profile.copyWith(bodyweightKg: 70.0);
        expect(updated.bodyweightKg, 70.0);
        expect(profile.bodyweightKg, isNull);
      });

      test('two profiles with different bodyweightKg are not equal', () {
        const a = Profile(id: 'user-1', bodyweightKg: 70.0);
        const b = Profile(id: 'user-1', bodyweightKg: 80.0);
        expect(a, isNot(equals(b)));
      });
    });
  });
}
