import '../../personal_records/models/personal_record.dart';

/// Hero-PR scoring function — `weight × reps`.
///
/// **Shared single source of truth.** Both [PostSessionChoreographer._buildPrCut]
/// (cinematic Beat 3 hero) AND `SharePayload.fromPostSessionState` (share-card
/// hero) sort PRs by this score. Divergence between the two ranking functions
/// would let the share card surface a different PR than the cinematic cut,
/// breaking the invariant pinned in `SharePayload.fromPostSessionState`'s
/// dartdoc: "Mirrors `PostSessionChoreographer._buildPrCut` so the share card
/// and the cinematic PR cut surface the same PR."
///
/// **Null reps → score 0.** Bodyweight-only PRs (where [PersonalRecord.reps]
/// is `null`) score zero and are dominated by any weighted PR with at least
/// one rep. This matches the choreographer's behavior pre-refactor — the
/// share card composer previously diverged by defaulting null reps to `1`,
/// which produced a different hero in mixed-PR sessions (one weighted + one
/// bodyweight). The score-zero rule is intentional: bodyweight PRs are surfaced
/// via the `maxReps` cinematic Beat 3 path (Phase 21), not the `weight × reps`
/// hero slot. Mockup §5 State 4 specifies "highest weight × reps".
///
/// Pure function. Deterministic. Safe to call from both Dart isolates and
/// Riverpod providers — no Flutter / framework dependencies.
double prScore(PersonalRecord pr) {
  final w = pr.value;
  final r = (pr.reps ?? 0).toDouble();
  return w * r;
}
