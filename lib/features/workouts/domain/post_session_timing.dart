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
/// **2026-05-23 retune (pass 1) — first-exposure parse-time floors revisited
/// (UX-critic analysis, in-flight PR 30a UX pass).** Initial constants were
/// specced against a second-exposure parse window (when the mid-workout
/// flash layer still pre-cued every reward event); the Path A pivot killed
/// that layer entirely, so every cut on this screen now lands as the user's
/// FIRST sighting of the event. On-device user feedback was "cinematic flows
/// too fast, almost no feeling of accomplishment." All cut hold durations
/// were bumped 200-700ms across the board to honor first-exposure parse time.
///
/// **2026-05-23 retune (pass 2) — match mockup §5 State 10's 12s ceiling.**
/// On-device verification of pass 1 (commit `2b26d60`) reported "timing
/// still feels super fast" and — critically — that the user "couldn't even
/// try to use the skip button" before cuts advanced. Pass 1 undershot the
/// canonical mockup budget. Pass 2 bumps every hold to land the max-combo
/// 5-cut total at ~12.2s (mockup §5 State 10 spec: "Total 12s — earned, not
/// indulgent"). The 12s ceiling is reserved for the rarest co-occurrence
/// (PR + rank-up + level-up + class-change in the same session); the
/// baseline 2-cut path still totals ~4.5s, which doesn't feel indulgent.
///
/// Math check for pass 2 max-combo (5 cuts): B1(2500) + B2 cascade(2800) +
/// B2 elevated(2200) + B3 PR(2500) + B3 title(2200) = 12 200 ms.
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
  /// Retuned 1200ms → 1800ms (pass 1, 2026-05-23) → 2500ms (pass 2,
  /// 2026-05-23) to match mockup §5 State 10's 12s max-combo ceiling.
  static const Duration b1HoldBaseline = Duration(milliseconds: 2500);

  /// Day-zero B1 hold — extended over baseline to honor first-step gravity.
  /// Mockup §2 Variant Day-Zero. Retuned 1300ms → 2000ms (pass 1) → 2600ms
  /// (pass 2) in proportion to the baseline retune.
  static const Duration b1HoldDayZero = Duration(milliseconds: 2600);

  /// Threshold-anticipatory B1 hold (fires for PR-incoming OR rank-up-incoming).
  /// The copy ("NOVO LIMITE.") carries the tension. Mockup §2 Variant
  /// Threshold-anticipatory + §2 RewardTier.derive note (accepts
  /// `hasPR || hasRankUp`). Retuned 1200ms → 1800ms (pass 1) → 2500ms
  /// (pass 2) — moves in lockstep with baseline.
  static const Duration b1HoldThresholdAnticipatory = Duration(
    milliseconds: 2500,
  );

  /// Class-change anticipatory / max-combo / level-up B1 hold. Longer parse
  /// time for the level-up announcement that's folded into B1 copy.
  /// Mockup §2 Variant Max-combo / Class-change. Retuned 1500ms → 2000ms
  /// (pass 1) → 2700ms (pass 2).
  static const Duration b1HoldClassChangeAnticipatory = Duration(
    milliseconds: 2700,
  );

  /// Pre-roll dead-black hold for the class-change / max-combo / level-up
  /// variants — 120ms of hairline-only abyss before the XP slam lands.
  /// Mockup §2 Variant Max-combo / Class-change.
  static const Duration b1PreRollClassChangeAnticipatory = Duration(
    milliseconds: 120,
  );

  /// Title-anticipatory shares B1 timing with Threshold-anticipatory (the
  /// title's gold pre-tint is omitted — same parse window, different copy).
  /// Mockup §2 note below the variant grid. Retuned in lockstep with the
  /// threshold-anticipatory token (pass 1 1800ms, pass 2 2500ms).
  static const Duration b1HoldTitleAnticipatory = Duration(milliseconds: 2500);

  // ─── Beat 2 (body-part tally) ────────────────────────────────────────

  /// Single-BP B2 hold. Mockup §3 Variant A. Retuned 1000ms → 1400ms
  /// (pass 1) → 2000ms (pass 2) — first-exposure parse floor for the
  /// body-part tally cut at the mockup-spec ceiling.
  static const Duration b2HoldSingle = Duration(milliseconds: 2000);

  /// Sequential B2 dominant-cut hold. Mockup §3 Variant B. Retuned 1000ms →
  /// 1400ms (pass 1) → 2000ms (pass 2) — moves in lockstep with the
  /// single-BP variant; both are first-exposure dominant reveals.
  static const Duration b2HoldSequentialDominant = Duration(milliseconds: 2000);

  /// Sequential B2 secondary-cut hold. Mockup §3 Variant B. Retuned 800ms →
  /// 1100ms (pass 1) → 1500ms (pass 2) — secondary hold stays ~500ms
  /// shorter than dominant so the rhythm reads as "main beat → echo."
  static const Duration b2HoldSequentialSecondary = Duration(
    milliseconds: 1500,
  );

  /// Cascade B2 hold (3+ BPs). Mockup §3 Variant C. Retuned 2000ms → 2800ms
  /// (pass 2, 2026-05-23) — the cascade holds N rows of stagger inside the
  /// same window, so the bump honors first-exposure parse time for the
  /// composed reveal AND lifts the max-combo budget to the mockup spec.
  static const Duration b2HoldCascade = Duration(milliseconds: 2800);

  /// Cascade row stagger — each additional BP fades in 140ms after the
  /// previous. Mockup §3 Variant C.
  static const Duration b2CascadeRowStagger = Duration(milliseconds: 140);

  /// Elevated B2 hold (rank-up fusion). Mockup §3 Variant D. Retuned 1100ms
  /// → 1600ms (pass 1) → 2200ms (pass 2) — elevated holds the bar-fill
  /// animation + rank slam in the same cut, so the floor grows with the
  /// composed reveal.
  static const Duration b2HoldElevated = Duration(milliseconds: 2200);

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

  /// PR gold-flood hold for the single-PR variant. Mockup §4 PR single.
  /// Retuned 1500ms → 1800ms (pass 1) → 2500ms (pass 2) — PR is the
  /// session's single most-celebratory event; the floor accommodates the
  /// white flash → eyebrow → hero → copy line parse chain at first
  /// exposure.
  static const Duration b3HoldPr = Duration(milliseconds: 2500);

  /// PR gold-flood hold for the multi-PR variant. Mockup §4 PR multi.
  /// Distinct from [b3HoldPr] because the multi variant additionally
  /// staggers N PR pills into the gold-flood window (200ms each via
  /// [b3MultiPrPillStagger]); the hero + pills + copy chain needs more
  /// parse headroom than the single-PR cut. Introduced 2026-05-23 (pass 1).
  /// Pass 2 lifts 2200ms → 3000ms — the multi variant carries the most
  /// composed reveal in the cinematic. The screen layer branches on
  /// `cut.pillRows.isNotEmpty` — same `isMulti` predicate that already
  /// drives the eyebrow + copy line resolver, so the timing branch and the
  /// rendering branch agree by construction.
  static const Duration b3HoldPrMulti = Duration(milliseconds: 3000);

  /// Multi-PR pill stagger — each additional PR pill fades in 200ms after
  /// the prior one inside the gold-flood context. Mockup §4 PR multi.
  static const Duration b3MultiPrPillStagger = Duration(milliseconds: 200);

  /// Title-unlock hold. Quieter than PR — no white flash. Mockup §4 Title.
  /// Retuned 1200ms → 1600ms (pass 1) → 2200ms (pass 2).
  static const Duration b3HoldTitle = Duration(milliseconds: 2200);

  /// Class-change hold. Longest single-cut budget in the cinematic — the
  /// rarest event earns the longest hold. Mockup §4 Class change + §5
  /// State 9 script. Retuned 1500ms → 2800ms (pass 2, 2026-05-23) — class
  /// change is the rarest event in the cinematic, lifted to honor the
  /// mockup's "rarity earns gravity" rule.
  static const Duration b3HoldClassChange = Duration(milliseconds: 2800);

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
