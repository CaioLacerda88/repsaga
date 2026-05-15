// Tests for [XpEvent.fromJson] payload-promotion (Phase 24a, PR #222;
// Phase 24c extension).
//
// The `difficulty_mult` field on `XpEvent` is NOT a top-level column on
// `xp_events` — it's snapshotted INSIDE `payload` by the SQL RPCs in
// migration 00054 (`record_set_xp`, `record_session_xp_batch`,
// `_rpg_backfill_chunk`). The custom `fromJson` factory promotes
// `payload.difficulty_mult` to the top level so the generated
// deserializer reads it where it expects. Without this promotion every
// event ever written would have `difficultyMult == null`, defeating
// the snapshot's purpose (per PR #222 reviewer Blocker).
//
// Phase 24c extends the same promotion to two more payload-nested
// keys snapshotted by migration 00057's RPCs: `effective_load` (the
// load actually plugged into the formula at write time) and
// `bodyweight_used` (whether the exercise's `uses_bodyweight_load`
// flag was TRUE when the event was written). Same payload-snapshot
// rationale, same forward-only contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/xp_event.dart';

// Sentinel value used by `baseRow` to distinguish "caller did not pass
// this optional top-level key" from "caller explicitly passed null".
// We need the latter to test the idempotency path where a top-level
// key is present-but-null and must NOT trigger payload promotion.
const Object _absent = Object();

void main() {
  // Common skeleton for a real `xp_events` row. Each test mutates the
  // payload / top-level keys to exercise a specific promotion branch.
  Map<String, dynamic> baseRow({
    Map<String, dynamic>? payload,
    double? topLevelDifficultyMult,
    Object? topLevelEffectiveLoad = _absent,
    Object? topLevelBodyweightUsed = _absent,
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
    if (!identical(topLevelEffectiveLoad, _absent)) {
      row['effective_load'] = topLevelEffectiveLoad;
    }
    if (!identical(topLevelBodyweightUsed, _absent)) {
      row['bodyweight_used'] = topLevelBodyweightUsed;
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

  group('XpEvent.fromJson — payload-promotion (Phase 24c)', () {
    test('promotes payload.effective_load when top-level key is absent '
        '(production path: real xp_events rows from migration 00057)', () {
      // Production xp_events row written by Phase-24c RPCs:
      // effective_load lives INSIDE payload alongside the rest of
      // the per-set breakdown. The top-level key is absent.
      final json = baseRow(
        payload: <String, dynamic>{
          'volume_load': 720.0,
          'base_xp': 80.0,
          'intensity_mult': 1.0,
          'strength_mult': 1.0,
          'difficulty_mult': 1.10,
          'effective_load': 90.0, // pull-up: bodyweight 70 + added 20
          'set_xp': 88.0,
        },
      );

      final event = XpEvent.fromJson(json);

      expect(
        event.effectiveLoad,
        equals(90.0),
        reason:
            'XpEvent.fromJson must promote payload.effective_load to '
            'the top level so the generated deserializer reads it. '
            'Without promotion the snapshot is silently lost and audit '
            'trails / replays show null instead of the real load.',
      );
      // Sanity: the rest deserialized normally.
      expect(event.eventType, equals('set'));
    });

    test('promotes payload.bodyweight_used when top-level key is absent '
        '(production path: real xp_events rows from migration 00057)', () {
      // Production row for a bodyweight-flagged exercise (e.g.
      // pull-up): the SQL RPC stamps bodyweight_used=true into
      // payload.
      final json = baseRow(
        payload: <String, dynamic>{
          'volume_load': 350.0,
          'base_xp': 50.0,
          'effective_load': 70.0,
          'bodyweight_used': true,
          'set_xp': 50.0,
        },
      );

      final event = XpEvent.fromJson(json);

      expect(
        event.bodyweightUsed,
        isTrue,
        reason:
            'XpEvent.fromJson must promote payload.bodyweight_used to '
            'the top level. Without promotion every event would read '
            'as null/false, losing the audit trail of which sets used '
            'the bodyweight-load semantics.',
      );
    });

    test('promotes both effective_load AND bodyweight_used together '
        '(typical Phase 24c production case)', () {
      // The realistic Phase 24c production payload: a bodyweight set
      // carries both keys at once. This is the case the SQL RPCs in
      // migration 00057 emit for every set on a flagged exercise.
      final json = baseRow(
        payload: <String, dynamic>{
          'volume_load': 600.0,
          'base_xp': 70.0,
          'intensity_mult': 1.0,
          'strength_mult': 1.05,
          'difficulty_mult': 1.15,
          'effective_load': 75.0, // dips: bodyweight 70 + added 5
          'bodyweight_used': true,
          'set_xp': 84.5,
        },
      );

      final event = XpEvent.fromJson(json);

      expect(
        event.effectiveLoad,
        equals(75.0),
        reason: 'effective_load must promote when present in payload.',
      );
      expect(
        event.bodyweightUsed,
        isTrue,
        reason: 'bodyweight_used must promote when present in payload.',
      );
      // Difficulty mult from Phase 24a still promotes correctly when
      // the 24c keys are also present — proves multi-key promotion.
      expect(
        event.difficultyMult,
        equals(1.15),
        reason: 'Adding 24c promotion did not break 24a promotion.',
      );
    });

    test('legacy events (Phase 24a era) keep effectiveLoad AND '
        'bodyweightUsed null — null is distinct from false', () {
      // A row written by Phase-24a RPCs (migration 00054) has
      // difficulty_mult in payload but neither of the 24c keys
      // anywhere. Both new fields must be null — NOT false. Null
      // semantically means "we don't know" and downstream consumers
      // (analytics, debug screens) must not treat legacy events as
      // "bodyweight_used = false".
      final json = baseRow(
        payload: <String, dynamic>{
          'volume_load': 480.0,
          'base_xp': 65.5,
          'intensity_mult': 1.0,
          'strength_mult': 1.0,
          'difficulty_mult': 1.21,
          'set_xp': 678.4,
        },
      );

      final event = XpEvent.fromJson(json);

      expect(
        event.effectiveLoad,
        isNull,
        reason:
            'Pre-24c events must deserialize cleanly with '
            'effectiveLoad = null. Consumers should fall back to the '
            'set\'s entered weight if they need a value.',
      );
      expect(
        event.bodyweightUsed,
        isNull,
        reason:
            'Pre-24c events must keep bodyweightUsed null — not '
            'false. Null means "unknown / pre-snapshot"; false means '
            '"flag was explicitly off at write time". Conflating them '
            'would let downstream analytics report misleading rates.',
      );
      // Phase 24a snapshot still works on the same row (regression).
      expect(event.difficultyMult, equals(1.21));
    });

    test('idempotent: top-level effective_load + bodyweight_used win '
        'over payload values (defensive / future-proofing path)', () {
      // Defensive scenario: if a future migration promotes either
      // key to a real top-level column, the factory must use the
      // top-level value as-is and IGNORE any payload value. We seed
      // payload with conflicting values to prove the top-level wins.
      final json = baseRow(
        topLevelEffectiveLoad: 100.0,
        topLevelBodyweightUsed: false,
        payload: <String, dynamic>{
          'effective_load': 50.0, // payload value should be ignored
          'bodyweight_used': true, // payload value should be ignored
          'set_xp': 100.0,
        },
      );

      final event = XpEvent.fromJson(json);

      expect(
        event.effectiveLoad,
        equals(100.0),
        reason:
            'Top-level effective_load must take precedence over the '
            'payload-nested value (idempotency / future-proofing).',
      );
      expect(
        event.bodyweightUsed,
        isFalse,
        reason:
            'Top-level bodyweight_used must take precedence over the '
            'payload-nested value (idempotency / future-proofing).',
      );
    });

    test('regression: Phase 24a difficulty_mult promotion still works '
        'after adding 24c keys (no cross-key interference)', () {
      // Pin that the additive 24c logic did not break the 24a
      // promotion path. This row carries ONLY difficulty_mult inside
      // payload — neither of the 24c keys is present anywhere.
      // Removing the difficulty_mult promotion branch from the
      // factory must still cause this assertion to fail.
      final json = baseRow(
        payload: <String, dynamic>{
          'volume_load': 480.0,
          'base_xp': 65.5,
          'difficulty_mult': 1.21,
          'set_xp': 678.4,
        },
      );

      final event = XpEvent.fromJson(json);

      expect(
        event.difficultyMult,
        equals(1.21),
        reason:
            'Phase 24a behavior must survive the 24c extension. If '
            'this fails, the 24c factory rewrite broke the 24a '
            'promotion path.',
      );
      // Sanity: 24c keys correctly remain null when not present.
      expect(event.effectiveLoad, isNull);
      expect(event.bodyweightUsed, isNull);
    });
  });
}
