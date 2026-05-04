/// Per-row PR display state for the active-workout set table (Phase 20).
///
/// Each set row in the active workout screen maps to exactly one of these
/// five states. The state is computed by [resolveRowStates] in
/// `pr_row_state_resolver.dart` from the workout's current set list and the
/// canonical historical [PersonalRecord]s for the exercise.
///
/// The state drives Direction B's row chrome (left rune-stripe, background
/// tint, value text color, done-mark, right bracket) per the locked spec in
/// `PLAN.md` Phase 20 → 5-state row matrix.
///
/// **Standing-vs-superseded semantic.** A "PR" in this enum is a *currently
/// standing* record — the best across all history INCLUDING this workout's
/// own earlier sets. A set that briefly held a PR mid-workout but was beaten
/// by a later set is [completedSupersededPr], not [completedStandingPr]. This
/// is the locked design decision (signed off 2026-05-04): gold means "best
/// you've ever done," nothing else.
///
/// **Multi-recordType binary rule.** A single set can simultaneously break
/// the heaviest-weight PR, the most-reps PR, and the highest-volume PR.
/// Visually it stays one row in one state. The row is [completedStandingPr]
/// if ANY of its broken record types is still standing within the workout;
/// it falls to [completedSupersededPr] only when EVERY type it broke has
/// since been superseded by a later set in the same workout. Multi-PR
/// celebration belongs in the post-workout summary, not the row chrome.
enum PrRowState {
  /// Pending set with no projected PR. Plain row chrome.
  ///
  /// The set is not yet completed AND, if it WERE completed at its current
  /// weight/reps, would not produce any new PR (every value is at-or-below
  /// the current standing record for each applicable record type).
  none,

  /// Pending set whose current values WOULD produce a PR if completed now.
  ///
  /// Predicted-PR is hypothetical — the set is not yet committed. The
  /// projection uses the same comparison rules as canonical PR detection
  /// (`PRDetectionService`): strict-greater than the standing record AND
  /// strict-greater than every earlier completed set in this same workout.
  pendingPredictedPr,

  /// Completed set that did not produce any new PR.
  completedNonPr,

  /// Completed set that DID produce a PR at the moment of completion, but a
  /// LATER completed set in the same workout has since superseded EVERY
  /// record type this set held. Renders with the muted "ghost-tinted" chrome
  /// (3dp success stripe + 2% gold tint + cream value), distinct from both
  /// plain completed and standing-PR.
  completedSupersededPr,

  /// Completed set that currently holds the standing record for at least one
  /// record type, across all history including this workout. Renders with
  /// the full gold treatment (4dp gold rune-stripe, 4% gold background tint,
  /// gold value text, 4dp gold right bracket).
  completedStandingPr,
}
