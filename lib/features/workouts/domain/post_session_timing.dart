/// Timing constants for the post-session cinematic (Phase 30 PR 30a).
///
/// **Why a central constants file (Decoupling Rule 10):** the 3-beat
/// post-session cinematic threads 7 cut widgets, an orchestrating
/// `AnimationController`, a state machine, and a summary panel — all
/// reading the same hold durations / pre-roll / abyss-gap values. Promoting
/// these to a single file means a future tuning pass touches one location;
/// a future maintainer chasing a "Beat 2 feels too short" complaint has
/// one place to look. Magic numbers spread across 7 widget files would be
/// the cluster `feedback_fixed_values_in_design` waiting to happen.
///
/// **Per the post-session mockup v2 (`docs/post-session-screen-mockup-v2.html`)
/// §2 + §5 storyboards (rewritten 2026-05-22, Path A pivot):** all hold
/// durations are minimum parse times for first-exposure revelations, not
/// confirmation-mode rests. Path A killed the mid-workout flash layer; every
/// cut on this screen is the user's first sighting of the event. Treat
/// scripted hold values as floors (parse-time guarantees), not ceilings.
///
/// **Why all-static (no enum-of-durations):** these are constants, not
/// variants. An enum would force every consumer to pattern-match on a
/// variant when they just need the number. The class form keeps them
/// `const`-folded at compile time.
library;

class PostSessionTiming {
  const PostSessionTiming._();

  // ─── Beat 1 (XP cut) ─────────────────────────────────────────────────

  /// Baseline B1 hold. Used by `RewardTier.baseline`. Mockup §2 Variant Baseline.
  static const Duration b1HoldBaseline = Duration(milliseconds: 1200);

  /// Day-zero B1 hold — extended 100ms over baseline to honor first-step
  /// gravity. Mockup §2 Variant Day-Zero.
  static const Duration b1HoldDayZero = Duration(milliseconds: 1300);

  /// Threshold-anticipatory B1 hold (fires for PR-incoming OR rank-up-incoming).
  /// Same 1200ms as baseline; the copy ("NOVO LIMITE.") carries the tension.
  /// Mockup §2 Variant Threshold-anticipatory + §2 RewardTier.derive note
  /// (Threshold-anticipatory accepts `hasPR || hasRankUp`).
  static const Duration b1HoldThresholdAnticipatory = Duration(
    milliseconds: 1200,
  );

  /// Class-change anticipatory / max-combo / level-up B1 hold. Longer parse
  /// time for the level-up announcement that's folded into B1 copy.
  /// Mockup §2 Variant Max-combo / Class-change.
  static const Duration b1HoldClassChangeAnticipatory = Duration(
    milliseconds: 1500,
  );

  /// Pre-roll dead-black hold for the class-change / max-combo / level-up
  /// variants — 120ms of hairline-only abyss before the XP slam lands.
  /// Mockup §2 Variant Max-combo / Class-change.
  static const Duration b1PreRollClassChangeAnticipatory = Duration(
    milliseconds: 120,
  );

  /// Title-anticipatory shares B1 timing with Threshold-anticipatory (the
  /// title's gold pre-tint is omitted — same parse window, different copy).
  /// Mockup §2 note below the variant grid.
  static const Duration b1HoldTitleAnticipatory = Duration(milliseconds: 1200);

  // ─── Beat 2 (body-part tally) ────────────────────────────────────────

  /// Single-BP B2 hold. Mockup §3 Variant A.
  static const Duration b2HoldSingle = Duration(milliseconds: 1000);

  /// Sequential B2 dominant-cut hold. Mockup §3 Variant B.
  static const Duration b2HoldSequentialDominant = Duration(milliseconds: 1000);

  /// Sequential B2 secondary-cut hold. Mockup §3 Variant B.
  static const Duration b2HoldSequentialSecondary = Duration(milliseconds: 800);

  /// Cascade B2 hold (3+ BPs). Locked at 2.0s regardless of N to keep the
  /// cinematic tight. Mockup §3 Variant C.
  static const Duration b2HoldCascade = Duration(milliseconds: 2000);

  /// Cascade row stagger — each additional BP fades in 140ms after the
  /// previous. Mockup §3 Variant C.
  static const Duration b2CascadeRowStagger = Duration(milliseconds: 140);

  /// Elevated B2 hold (rank-up fusion). Mockup §3 Variant D.
  static const Duration b2HoldElevated = Duration(milliseconds: 1100);

  /// Bar-fill animation duration inside an elevated B2. Bar runs to 100%
  /// over this window before the rank slam fires. Mockup §3 Variant D
  /// + §5 State 5 script.
  static const Duration b2ElevatedBarFill = Duration(milliseconds: 400);

  /// Brief flash between bar fill complete and rank slam in elevated B2.
  /// Mockup §5 State 5 script.
  static const Duration b2ElevatedRankFlash = Duration(milliseconds: 80);

  // ─── Beat 3 (reward cuts) ────────────────────────────────────────────

  /// White-flash duration that precedes the PR gold flood. Single white
  /// flash per session — multi-PR adds pills inside the gold context, not
  /// a second flash. Mockup §4 PR single + §4 PR multi.
  static const Duration b3PrWhiteFlash = Duration(milliseconds: 33);

  /// PR gold-flood hold (single OR multi-PR hero). Mockup §4 PR.
  static const Duration b3HoldPr = Duration(milliseconds: 1500);

  /// Multi-PR pill stagger — each additional PR pill fades in 200ms after
  /// the prior one inside the gold-flood context. Mockup §4 PR multi.
  static const Duration b3MultiPrPillStagger = Duration(milliseconds: 200);

  /// Title-unlock hold. Quieter than PR — no white flash. Mockup §4 Title.
  static const Duration b3HoldTitle = Duration(milliseconds: 1200);

  /// Class-change hold. Longest single-cut budget in the cinematic — the
  /// rarest event earns the longest hold. Mockup §4 Class change + §5
  /// State 9 script.
  static const Duration b3HoldClassChange = Duration(milliseconds: 1500);

  // ─── Transitions ─────────────────────────────────────────────────────

  /// Abyss gap between consecutive cuts. A brief blackout frame so the
  /// hard cut reads as a cut, not a crossfade. Mockup §5 storyboard
  /// "gap33" markers.
  static const Duration cutAbyssGap = Duration(milliseconds: 33);

  // ─── Gestures ────────────────────────────────────────────────────────

  /// Long-press threshold to skip the entire cinematic and jump to the
  /// summary panel. Mockup §8 gap 6.
  static const Duration skipToSummaryLongPress = Duration(milliseconds: 500);
}
