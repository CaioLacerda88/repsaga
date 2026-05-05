import '../../personal_records/models/record_type.dart';

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

/// Per-row PR display data — the [PrRowState] plus the set of [RecordType]s
/// that drive the row's value-text accent (Phase 20 commit 4).
///
/// Two pieces of information the row widget needs to render correctly:
///
///   1. **state** — picks the chrome (left stripe color/width, background
///      tint, done-mark, right bracket) per the 5-state matrix.
///   2. **accentTypes** — picks WHICH value(s) on the row carry the accent
///      (gold for predicted/standing, cream for superseded). A single set
///      can simultaneously break heaviest-weight, max-reps and max-volume,
///      so this is a [Set] not a single value.
///
/// **Per-state semantics of [accentTypes]:**
///
///   * [PrRowState.none] / [PrRowState.completedNonPr] → empty (no accent).
///   * [PrRowState.pendingPredictedPr] → the record types the row's CURRENT
///     values would break if the set were completed now. Both weight and
///     reps Text widgets in the row check this set; if the corresponding
///     [RecordType] is present, the value renders gold.
///   * [PrRowState.completedStandingPr] → the record types the row broke
///     at completion AND that are STILL the standing best within the
///     workout. (E.g. row N broke weight + volume, a later set superseded
///     volume but not weight; this set contains only [RecordType.maxWeight].)
///   * [PrRowState.completedSupersededPr] → the record types the row broke
///     at the moment of completion (all of which have since been
///     superseded). The values render cream-700 (not dim, not gold) so the
///     row reads as "you got there, but a later set went further" without
///     stealing the standing-PR's gold.
///
/// **Mapping [RecordType] → on-screen value:**
///
///   * [RecordType.maxWeight] → the WEIGHT cell (kg/lb value).
///   * [RecordType.maxReps]   → the REPS cell.
///   * [RecordType.maxVolume] → BOTH cells together carry the accent. Volume
///     is `weight × reps`, so the volume PR is visually attributable to the
///     pair, not a single number. The widget folds maxVolume into BOTH the
///     weight-accent and reps-accent checks so a volume-only PR still shows
///     the achievement on the row.
class PrRowDisplay {
  const PrRowDisplay({required this.state, required this.accentTypes});

  /// Convenience for the no-accent rows ([PrRowState.none] and
  /// [PrRowState.completedNonPr]).
  const PrRowDisplay.plain(this.state) : accentTypes = const <RecordType>{};

  final PrRowState state;
  final Set<RecordType> accentTypes;

  /// Whether the WEIGHT value cell should carry the row's accent color.
  ///
  /// True when [accentTypes] contains [RecordType.maxWeight] OR
  /// [RecordType.maxVolume] — volume is a (weight × reps) compound and the
  /// row chooses to highlight BOTH operands so a volume-only PR doesn't
  /// look unaccented.
  bool get isWeightAccented =>
      accentTypes.contains(RecordType.maxWeight) ||
      accentTypes.contains(RecordType.maxVolume);

  /// Whether the REPS value cell should carry the row's accent color.
  ///
  /// True when [accentTypes] contains [RecordType.maxReps] OR
  /// [RecordType.maxVolume] — see [isWeightAccented] for the volume-folding
  /// rationale.
  bool get isRepsAccented =>
      accentTypes.contains(RecordType.maxReps) ||
      accentTypes.contains(RecordType.maxVolume);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PrRowDisplay &&
          state == other.state &&
          _setEquals(accentTypes, other.accentTypes));

  @override
  int get hashCode => Object.hash(state, _setHash(accentTypes));

  @override
  String toString() => 'PrRowDisplay($state, $accentTypes)';
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) return false;
  for (final e in a) {
    if (!b.contains(e)) return false;
  }
  return true;
}

int _setHash<T>(Set<T> s) {
  // Order-independent hash: XOR of element hashes. Acceptable for a small
  // domain set (3 record types).
  var h = 0;
  for (final e in s) {
    h ^= e.hashCode;
  }
  return h;
}
