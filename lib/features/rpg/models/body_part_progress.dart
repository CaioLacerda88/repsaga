// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

import 'body_part.dart';

part 'body_part_progress.freezed.dart';
part 'body_part_progress.g.dart';

/// Materialized per-`(user_id, body_part)` state.
///
/// One row per body part per user. Updated incrementally by the
/// `record_set_xp` RPC during a workout save (live path) and by the
/// `backfill_rpg_v1` procedure (backfill path) — both produce identical
/// rows for identical inputs (parity invariant validated by integration
/// tests).
///
/// `rank` is **derived but cached** so the character sheet doesn't need to
/// rerun `rank_for_xp(total_xp)` on every read. Permanent monotonic
/// invariant: no code path may decrease `rank` or `vitalityPeak`. The
/// repository layer rejects writes that would (idempotency-via-comparison,
/// not idempotency-via-flag).
@freezed
abstract class BodyPartProgress with _$BodyPartProgress {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory BodyPartProgress({
    required String userId,
    required BodyPart bodyPart,
    required double totalXp,
    required int rank,
    required double vitalityEwma,
    required double vitalityPeak,
    // Decaying reference peak (00083) — the post-session conditioning charge
    // fraction's denominator (`ewma / refPeak`). Distinct from `vitalityPeak`
    // (monotone career-best, Saga screen): this forgets stale peaks over ~3
    // weeks so a detrained comeback reads meaningfully. Parsed from
    // `vitality_ref_peak` via the no-arg `select()`.
    required double vitalityRefPeak,
    DateTime? lastEventAt,
    required DateTime updatedAt,
  }) = _BodyPartProgress;

  factory BodyPartProgress.fromJson(Map<String, dynamic> json) =>
      _$BodyPartProgressFromJson(json);
}
