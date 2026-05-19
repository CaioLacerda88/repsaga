import '../../rpg/models/character_sheet_state.dart';

/// Picks the body-part entry with the smallest absolute XP gap to its next
/// rank. Used by the Home character card collapsed-state indicator
/// ("closest to ranking up" nudge).
///
/// Excludes:
///   * Untrained entries (`entry.isUntrained == true`) — no meaningful next
///     rank target yet.
///   * Max-rank entries (`xpForNextRank == 0`) — no next rank exists, so the
///     gap is undefined.
///
/// Returns null when no eligible entry exists (day-0 user where every active
/// part is untrained, or every active part is already at max rank).
///
/// Ties broken by canonical [BodyPart] enum order (the order entries appear
/// in `BodyPart.values`), so the result is deterministic across rebuilds
/// even when input list order varies.
BodyPartSheetEntry? closestRankUp(List<BodyPartSheetEntry> entries) {
  BodyPartSheetEntry? best;
  double bestGap = double.infinity;
  int bestIndex = 1 << 30;
  for (final e in entries) {
    if (e.isUntrained) continue;
    if (e.xpForNextRank <= 0) continue;
    final gap = e.xpForNextRank - e.xpInRank;
    final index = e.bodyPart.index;
    if (gap < bestGap || (gap == bestGap && index < bestIndex)) {
      bestGap = gap;
      bestIndex = index;
      best = e;
    }
  }
  return best;
}
