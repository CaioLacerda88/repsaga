// ignore_for_file: invalid_annotation_target

import 'package:flutter/material.dart' show Color;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/theme/app_theme.dart';
import '../../personal_records/domain/pr_detection_service.dart';
import '../../rpg/domain/body_part_hues.dart';
import '../../rpg/domain/celebration_queue.dart';
import '../../rpg/models/body_part.dart';
import '../../rpg/models/celebration_event.dart';
import 'pr_score.dart';
import 'reward_tier.dart';

part 'share_payload.freezed.dart';

/// Renderable variant of the share card.
///
/// **Achievement Frame (D3)** — the single photo-overlay treatment for the
/// photo path (Phase 31 lock; replaced Variant A + Variant B). Two
/// trapezoidal `ClipPath` collars frame the photo zone; 4dp side bars in
/// the dominant-BP hue (left) and `hotViolet` (right) encode body-part
/// identity in the chrome structure. See
/// `share_card_achievement_frame.dart` for the visual contract.
///
/// **Discreet** — no-photo cinematic still. Auto-selected when camera
/// permission is denied OR user taps "Sem foto · só a saga" on the bottom
/// sheet. Renders the saga events directly on a hue-flood gradient +
/// diagonal slash background; the photo path is replaced by chrome that
/// IS the brand surface (mockup §6 render rules).
enum ShareCardVariant { achievementFrame, discreet }

/// The PR triplet surfaced on the share card — already-resolved for display.
///
/// Carries only what the overlay needs to render the bottom-collar lift
/// detail "95kg × 5 · Supino" on the Achievement Frame (heroGold when
/// [pr] is non-null) or the "!! 95kg × 5" d-sub on Discreet. PR-by-band
/// breakdowns + multi-PR pill rows stay on the post-session cinematic
/// Beat 3 cut — the share card surfaces the hero PR only (mockup §6
/// callout: "the default surfaces only XP + peak event").
@freezed
abstract class SharePayloadPr with _$SharePayloadPr {
  const factory SharePayloadPr({
    /// Pre-resolved localized exercise name, e.g. "Supino reto" / "Bench Press".
    required String exerciseName,

    /// Hero PR weight in kilograms (chosen by score = weight × reps in the
    /// choreographer; see `PostSessionChoreographer._buildPrCut`).
    required double weightKg,

    /// Hero PR reps achieved at [weightKg]. `0` is a legal value for
    /// bodyweight-only exercises where the record type is `maxReps` —
    /// the choreographer surfaces those as a reps-only PR via the same
    /// hero plumbing, but the share overlay still renders the
    /// `weight × reps` line; on bodyweight exercises [weightKg] reads 0.
    required int reps,
  }) = _SharePayloadPr;
}

/// Snapshot of a finished workout, projected into the surface area the share
/// card needs to render.
///
/// Pure data composed from `(PostSessionState)` — the existing in-memory
/// snapshot built by `PostSessionController` at finish time. The composer
/// ([SharePayload.fromPostSessionState]) deliberately reads only the fields
/// the share card needs; the rest of the post-session state stays on the
/// cinematic side of the wall.
///
/// **Why a separate model instead of passing `PostSessionState` directly?**
///   1. Decoupling Rule 1 (pure data) — `PostSessionState` carries
///      `cuts`/`cutIndex`/`showSummary` runtime fields the share card has
///      no business reading. Projecting through a dedicated model means a
///      future refactor of the cinematic state machine cannot accidentally
///      break the share pipeline.
///   2. Testability — share-card widget tests build a `SharePayload` from
///      one Freezed constructor call. Building a full `PostSessionState`
///      with cuts + labels + rank progress just to test the share overlay
///      would force harness setup that the widget contract doesn't need.
///   3. Eventual persistence — Pass 3 introduces a "share preview screen"
///      that may suspend the workout-finish session and resume on relaunch.
///      Persisting a 6-field [SharePayload] is trivial; persisting the
///      whole cinematic state is not.
///
/// **Dominant body part** is the single source of truth for the hue accent.
/// Selection rules: highest XP delta → highest current rank → alphabetical
/// (matches `PostSessionChoreographer`'s rule so the share card's accent
/// matches the cinematic Beat 2 dominant BP). `null` means no XP was earned
/// on any body part this session — defensively falls back to the brand
/// hot violet via [SharePayload.dominantHue].
///
/// **Class slug** is the current character class (e.g. "bulwark"). On
/// class-change sessions this is the NEW class. The Achievement Frame's
/// top-collar class-name line renders this verbatim (caller uppercases);
/// the class-change Q4 lock keeps the "DESPERTOU" framing in the B3
/// cinematic cut, not on the share card.
@freezed
abstract class SharePayload with _$SharePayload {
  const SharePayload._();

  const factory SharePayload({
    /// The reward tier classification — drives variant copy hints and the
    /// "show share CTA at all?" branch upstream. Stored here so the share
    /// preview screen can re-classify without re-running `RewardTier.derive`.
    required RewardTier tier,

    /// Total XP earned this session (e.g. 618). Renders as `+618 XP` on
    /// the Achievement Frame's bottom-collar XP hero AND the Discreet's
    /// d-hero numeric.
    required int totalXp,

    /// Dominant body part — `null` if no BP earned XP this session (a
    /// pathological case; defensive null). Drives the hue accent across
    /// both variants (the Achievement Frame's left side bar + BP rank
    /// line color, plus the Discreet's eyebrow + slash). Selection logic
    /// mirrors `PostSessionChoreographer._appendBeat2`.
    required BodyPart? dominantBodyPart,

    /// Current rank on [dominantBodyPart] after the session. Renders in
    /// the Discreet eyebrow ("Peito · Rank 19") and the Achievement
    /// Frame's bottom-collar BP-rank line. `null` when [dominantBodyPart]
    /// is `null`.
    required int? dominantBodyPartRank,

    /// Fraction in `[0.0, 1.0]` of XP progress within the dominant BP's
    /// current rank — historically drove a mini progress-bar fill on the
    /// retired Variant A. Phase 31's Achievement Frame doesn't render a
    /// fill bar (chrome encodes BP identity in the side bars instead), so
    /// the field is currently read only by tests + the cinematic. `0.0`
    /// when [dominantBodyPart] is `null`. Computed upstream from
    /// `RankCurve.progressFraction(totalXp, rank)` so the value stays in
    /// lockstep with the saga screen's rank rail.
    required double rankProgressFraction,

    /// Hero PR data when the session set a new record. `null` on baseline
    /// + rank-up-only + class-change-only + title-only sessions.
    required SharePayloadPr? pr,

    /// Character class slug as of the post-session snapshot. e.g. "bulwark",
    /// "berserker", "initiate". Always non-null — every user has a class,
    /// even Initiate. Renders on the Achievement Frame's top-collar
    /// class-name line (caller uppercases). On class-change sessions
    /// this is already the NEW class slug (controller swaps before the
    /// payload is composed).
    required String characterClassSlug,

    /// `true` when the session crossed a class boundary (the queue carried
    /// a `ClassChangeEvent`). The Discreet variant overrides the dominant
    /// BP hue with brand `hotViolet` AND renders "BULWARK DESPERTOU." as
    /// the d-hero. The Achievement Frame swaps the LEFT side bar from
    /// the dominant hue (which is already `hotViolet` here per the
    /// [dominantHue] override) to `heroGold` so the chrome doesn't read
    /// as drained (both bars `hotViolet`). Top-collar copy stays as the
    /// new class name only — Q4 lock keeps "DESPERTOU" framing in the
    /// cinematic B3 cut, not on the card.
    required bool isClassChange,

    /// `true` when the session unlocked at least one title. Reserved for
    /// future copy hints — not rendered today but persisted on the payload
    /// so the preview-screen flow can branch without re-computing.
    required bool hasTitleUnlock,

    /// `true` when the session crossed at least one body-part rank
    /// threshold. Drives the rank-info-vs-PR-info copy branching at the
    /// screen-layer composer.
    required bool hasRankUp,
  }) = _SharePayload;

  /// Compose a [SharePayload] from a finished post-session snapshot.
  ///
  /// **Inputs (all already in `PostSessionState` after PR 30a):**
  ///   * [queueResult] — celebration queue (carries `RankUpEvent`,
  ///     `ClassChangeEvent`, `TitleUnlockEvent`).
  ///   * [tier] — `RewardTier.derive` output.
  ///   * [prResult] — `PRDetectionResult` from the finish flow.
  ///   * [bpXpDeltas] — `{BodyPart: xpEarnedThisSession}`. Drives dominant
  ///     BP selection.
  ///   * [bpRankAfter] — `{BodyPart: rankAfterSave}`. Read for the
  ///     dominant BP's rank.
  ///   * [bpProgressFractionAfter] — `{BodyPart: fraction in [0,1]}`.
  ///     Post-session XP progress within the BP's current rank, as already
  ///     computed by `PostSessionController.build` via
  ///     `RankCurve.progressFraction`. Looked up by `dominantBodyPart`.
  ///   * [exerciseNames] — pre-resolved exercise display names.
  ///   * [totalXp] — total XP earned this session.
  ///   * [characterClassSlug] — POST-session character class slug
  ///     (already updated if class change fired).
  ///
  /// **Dominant BP selection (matches choreographer):** highest XP delta
  /// → highest current rank → alphabetical `dbValue`. Empty deltas map
  /// give `dominantBodyPart == null`.
  ///
  /// **Hero PR selection (matches choreographer):** highest score
  /// `value × reps`, ties broken by exercise name (alphabetical). Mirrors
  /// `PostSessionChoreographer._buildPrCut` so the share card and the
  /// cinematic PR cut surface the same PR.
  ///
  /// **Idempotency:** same inputs → same output. Pure function. Safe to
  /// re-call from the preview screen on variant toggle without re-reading
  /// providers.
  factory SharePayload.fromPostSessionState({
    required RewardTier tier,
    required CelebrationQueueResult queueResult,
    required PRDetectionResult? prResult,
    required Map<BodyPart, int> bpXpDeltas,
    required Map<BodyPart, int> bpRankAfter,
    required Map<BodyPart, double> bpProgressFractionAfter,
    required Map<String, String> exerciseNames,
    required int totalXp,
    required String characterClassSlug,
  }) {
    // Dominant BP selection — same rule as
    // PostSessionChoreographer._appendBeat2 so the share card hue tracks
    // the cinematic Beat 2 dominant BP.
    BodyPart? dominantBp;
    int? dominantRank;
    if (bpXpDeltas.isNotEmpty) {
      final sorted = bpXpDeltas.keys.toList()
        ..sort((a, b) {
          final xpCmp = bpXpDeltas[b]!.compareTo(bpXpDeltas[a]!);
          if (xpCmp != 0) return xpCmp;
          final rankCmp = (bpRankAfter[b] ?? 1).compareTo(bpRankAfter[a] ?? 1);
          if (rankCmp != 0) return rankCmp;
          return a.dbValue.compareTo(b.dbValue);
        });
      dominantBp = sorted.first;
      dominantRank = bpRankAfter[dominantBp];
    }

    // Hero PR selection — matches PostSessionChoreographer._buildPrCut so
    // the share card surfaces the same PR the cinematic Beat 3 cut did.
    SharePayloadPr? heroPr;
    if (prResult != null && prResult.hasNewRecords) {
      final records = [...prResult.newRecords];
      records.sort((a, b) {
        final aScore = prScore(a);
        final bScore = prScore(b);
        final cmp = bScore.compareTo(aScore);
        if (cmp != 0) return cmp;
        final aName = exerciseNames[a.exerciseId] ?? a.exerciseId;
        final bName = exerciseNames[b.exerciseId] ?? b.exerciseId;
        return aName.compareTo(bName);
      });
      final hero = records.first;
      heroPr = SharePayloadPr(
        exerciseName: exerciseNames[hero.exerciseId] ?? hero.exerciseId,
        weightKg: hero.value,
        reps: hero.reps ?? 0,
      );
    }

    final hasClassChange = queueResult.queue.any((e) => e is ClassChangeEvent);
    final hasTitle = queueResult.queue.any((e) => e is TitleUnlockEvent);
    final hasRankUp = queueResult.queue.any((e) => e is RankUpEvent);

    // Rank progress lookup — defaults to 0.0 when no dominant BP OR the
    // BP is absent from the map (defensive; the controller always populates
    // it for every BP that earned XP this session).
    final rankProgress = (dominantBp == null)
        ? 0.0
        : (bpProgressFractionAfter[dominantBp] ?? 0.0).clamp(0.0, 1.0);

    return SharePayload(
      tier: tier,
      totalXp: totalXp,
      dominantBodyPart: dominantBp,
      dominantBodyPartRank: dominantRank,
      rankProgressFraction: rankProgress,
      pr: heroPr,
      characterClassSlug: characterClassSlug,
      isClassChange: hasClassChange,
      hasTitleUnlock: hasTitle,
      hasRankUp: hasRankUp,
    );
  }

  /// The hue color used as the accent across all three variants.
  ///
  /// Lookup is a pure function of [dominantBodyPart] + [isClassChange]:
  ///   * `isClassChange == true` → `AppColors.hotViolet` (mockup §6
  ///     Discreet render rules: class change overrides the BP hue).
  ///   * `dominantBodyPart != null` → the matching `AppColors.bodyPart*`
  ///     token (chest → pink, back → sky, legs → green, shoulders →
  ///     amber, arms → red, core → indigo, cardio → orange).
  ///   * `dominantBodyPart == null` → `AppColors.hotViolet` (defensive
  ///     fallback; the share CTA should never appear without a dominant
  ///     BP, but if it does we lead with the brand color).
  Color get dominantHue {
    if (isClassChange) return AppColors.hotViolet;
    final bp = dominantBodyPart;
    if (bp == null) return AppColors.hotViolet;
    return _bodyPartHue(bp);
  }
}

/// Whether the share CTA itself should render on the post-session summary
/// panel for a given payload.
///
/// Mirrors the rule pinned by `PostSessionStateX.hasShareCta` (mockup §5
/// states 1, 2, 7 omit the CTA; states 3, 4, 5, 6, 8, 9, 10 show it).
/// Lives here as an extension so screen-layer code can ask the payload
/// directly without re-deriving from the queue.
extension SharePayloadCta on SharePayload {
  bool get hasShareCta {
    if (pr != null) return true;
    if (hasRankUp) return true;
    if (hasTitleUnlock) return true;
    if (isClassChange) return true;
    return false;
  }
}

/// Body-part hue lookup — delegates to the canonical domain map
/// ([BodyPartHues.hueFor], §13.3 lock contract). Reading through the
/// single source of truth prevents drift between the share card and every
/// other "per-BP color" surface (stats trend chart, rank rail, weekly plan
/// engagement bars).
Color _bodyPartHue(BodyPart bp) => BodyPartHues.hueFor(bp);
