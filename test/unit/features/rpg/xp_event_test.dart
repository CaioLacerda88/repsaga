// Tests for [XpEvent.fromJson] payload-promotion (Phase 24a, PR #222).
//
// The `difficulty_mult` field on `XpEvent` is NOT a top-level column on
// `xp_events` — it's snapshotted INSIDE `payload` by the SQL RPCs in
// migration 00054 (`record_set_xp`, `record_session_xp_batch`,
// `_rpg_backfill_chunk`). The custom `fromJson` factory promotes
// `payload.difficulty_mult` to the top level so the generated
// deserializer reads it where it expects. Without this promotion every
// event ever written would have `difficultyMult == null`, defeating
// the snapshot's purpose (per PR #222 reviewer Blocker).

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/xp_event.dart';

void main() {
  // Common skeleton for a real `xp_events` row. Each test mutates the
  // payload / top-level keys to exercise a specific promotion branch.
  Map<String, dynamic> baseRow({
    Map<String, dynamic>? payload,
    double? topLevelDifficultyMult,
  }) {
    final row = <String, dynamic>{
      'id': '00000000-0000-0000-0000-000000000001',
      'user_id': '00000000-0000-0000-0000-000000000002',
      'event_type': 'set',
      'set_id': '00000000-0000-0000-0000-000000000003',
      'session_id': '00000000-0000-0000-0000-000000000004',
      'source_type': null,
      'source_payload': null,
      'payload': payload ?? <String, dynamic>{},
      'attribution': <String, dynamic>{'chest': 12.5},
      'total_xp': 12.5,
      'occurred_at': '2026-05-14T12:00:00.000Z',
      'created_at': '2026-05-14T12:00:00.000Z',
    };
    if (topLevelDifficultyMult != null) {
      row['difficulty_mult'] = topLevelDifficultyMult;
    }
    return row;
  }

  group('XpEvent.fromJson — payload-promotion (Phase 24a)', () {
    test('promotes payload.difficulty_mult when top-level key is absent '
        '(production path: real xp_events rows)', () {
      // Production xp_events row: difficulty_mult lives INSIDE payload,
      // not at the top level. Migration 00054's RPCs all write it this
      // way (see jsonb_build_object call sites).
      final json = baseRow(
        payload: <String, dynamic>{
          'volume_load': 480.0,
          'base_xp': 65.5,
          'intensity_mult': 1.0,
          'strength_mult': 1.0,
          'difficulty_mult': 1.21, // T2 deadlift composite
          'set_xp': 678.4,
        },
      );

      final event = XpEvent.fromJson(json);

      expect(
        event.difficultyMult,
        equals(1.21),
        reason:
            'XpEvent.fromJson must promote payload.difficulty_mult to '
            'the top level so the generated deserializer reads it. '
            'Without promotion the value is silently null and the '
            'snapshot is useless.',
      );
      // Sanity: the rest of the row deserialized normally.
      expect(event.eventType, equals('set'));
      expect(event.totalXp, equals(12.5));
    });

    test('leaves difficultyMult null for legacy events with no '
        'difficulty_mult key anywhere (forward-only contract)', () {
      // Phase 24a is forward-only: events written before migration
      // 00054 deployed don't carry the snapshot. Their payloads have
      // no difficulty_mult key and there's no top-level column.
      final json = baseRow(
        payload: <String, dynamic>{
          'volume_load': 200.0,
          'base_xp': 35.0,
          'intensity_mult': 1.0,
          'strength_mult': 1.0,
          'set_xp': 35.0,
        },
      );

      final event = XpEvent.fromJson(json);

      expect(
        event.difficultyMult,
        isNull,
        reason:
            'Legacy events (pre-Phase-24a) must deserialize cleanly '
            'with difficultyMult = null. Consumers that need a value '
            'should fall back to 1.0.',
      );
    });

    test('idempotent: when difficulty_mult is already at the top level '
        '(defensive path), uses it directly without re-promoting', () {
      // Defensive scenario: a hypothetical caller (or a future
      // migration that adds a real top-level column) hands us a row
      // where difficulty_mult is already at the top level. The
      // factory must use that value as-is and NOT re-read from
      // payload. We seed payload with a different value to prove the
      // top-level value wins.
      final json = baseRow(
        topLevelDifficultyMult: 0.95,
        payload: <String, dynamic>{
          'difficulty_mult': 1.25, // payload value should be ignored
          'set_xp': 100.0,
        },
      );

      final event = XpEvent.fromJson(json);

      expect(
        event.difficultyMult,
        equals(0.95),
        reason:
            'Top-level difficulty_mult must take precedence over the '
            'payload-nested value (idempotency / future-proofing).',
      );
    });

    test('handles legacy events with payload entirely absent of the key '
        'AND no top-level value (no NPE on payload?.[key])', () {
      // Same scenario as the legacy test above, but explicitly with
      // an empty payload map — exercises the `payload?[key]` null
      // safety path. (The legacy test uses a payload with other keys;
      // this one ensures an empty-but-present payload doesn't throw.)
      final json = baseRow(payload: <String, dynamic>{});

      final event = XpEvent.fromJson(json);

      expect(event.difficultyMult, isNull);
    });
  });
}
