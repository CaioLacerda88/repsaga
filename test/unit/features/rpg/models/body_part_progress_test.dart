import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/body_part_progress.dart';

void main() {
  group('BodyPartProgress.fromJson', () {
    test('parses vitality_ref_peak from the snake_case server key', () {
      // The repository fetches body_part_progress via a no-arg select(), so the
      // raw row carries `vitality_ref_peak` (00083). Pin that the model maps it
      // to vitalityRefPeak — distinct from vitality_peak (career best).
      final row = <String, dynamic>{
        'user_id': 'u1',
        'body_part': 'chest',
        'total_xp': 1234.5,
        'rank': 7,
        'vitality_ewma': 100.0,
        'vitality_peak': 900.0,
        'vitality_ref_peak': 773.99,
        'last_event_at': null,
        'updated_at': '2026-06-23T00:00:00.000Z',
      };

      final progress = BodyPartProgress.fromJson(row);

      expect(progress.bodyPart, BodyPart.chest);
      expect(progress.vitalityPeak, 900.0);
      expect(progress.vitalityRefPeak, 773.99);
      // ref_peak is independent of the career peak — they must not be conflated.
      expect(progress.vitalityRefPeak, isNot(progress.vitalityPeak));
    });
  });
}
