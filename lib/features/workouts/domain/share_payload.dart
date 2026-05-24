// ignore_for_file: invalid_annotation_target

import 'package:flutter/material.dart' show Color;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/theme/app_theme.dart';
import '../../personal_records/domain/pr_detection_service.dart';
import '../../personal_records/models/personal_record.dart';
import '../../rpg/domain/celebration_queue.dart';
import '../../rpg/models/body_part.dart';
import '../../rpg/models/celebration_event.dart';
import '../../rpg/ui/utils/vitality_state_styles.dart';
import 'reward_tier.dart';

part 'share_payload.freezed.dart';

/// Renderable variant of the share card.
///
/// **Variant A (Minimal Strip)** — bottom strip overlay, photo unobstructed.
/// Default for every session and every share target.
///
/// **Variant B (Full-Bleed Collars)** — top + bottom diagonal-cut collars
/// (`CustomClipper<Path>`). One-tap toggle on the preview screen
/// (mockup §6 "Tente o destaque" nudge for high-drama sessions).
///
/// **Discreet** — no-photo cinematic still. Auto-selected when camera
/// permission is denied OR user taps "Sem foto · só a saga" on the bottom
/// sheet. Uses the same Variant-A overlay pipeline; only the underlay
/// (photo vs hue-flood gradient + slash) differs (mockup §6 render rules).
enum ShareCardVariant { minimalStrip, fullBleed, discreet }

/// The PR triplet surfaced on the share card — already-resolved for display.
///
/// Carries only what the overlay needs to render the gold-tier "95kg × 5 · PR"
/// line (Variant A) / "!! Recorde" tag + lift detail (Variant B) / "!! 95kg × 5"
/// d-sub (Discreet). PR-by-band breakdowns + multi-PR pill rows stay on the
/// post-session cinematic Beat 3 cut — the share card surfaces the hero PR
/// only (mockup §6 callout: "the default surfaces only XP + peak event").
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
/// **Class slug** is `null` unless the queue carried a `ClassChangeEvent`.
/// Variant B's top-collar "BULWARK" line renders only when this is set;
/// when absent, the top collar shows the existing character class instead
/// (resolved at the screen layer from the user character snapshot — passed
/// in via [characterClassSlug]).
@freezed
abstract class SharePayload with _$SharePayload {
  const SharePayload._();

  const factory SharePayload({
    /// The reward tier classification — drives variant copy hints and the
    /// "show share CTA at all?" branch upstream. Stored here so the share
    /// preview screen can re-classify without re-running `RewardTier.derive`.
    required RewardTier tier,

    /// Total XP earned this session (e.g. 618). Renders as `+618 XP` on
    /// Variant A's bottom strip and `+618 XP` on Variant B's collar-bottom.
    required int totalXp,

    /// Dominant body part — `null` if no BP earned XP this session (a
    /// pathological case; defensive null). Drives the hue accent across
    /// all three variants. Selection logic mirrors
    /// `PostSessionChoreographer._appendBeat2`.
    required BodyPart? dominantBodyPart,

    /// Current rank on [dominantBodyPart] after the session. Renders in
    /// Discreet variant's eyebrow ("Peito · Rank 19"). `null` when
    /// [dominantBodyPart] is `null`.
    required int? dominantBodyPartRank,

    /// Hero PR data when the session set a new record. `null` on baseline
    /// + rank-up-only + class-change-only + title-only sessions.
    required SharePayloadPr? pr,

    /// Character class slug as of the post-session snapshot. e.g. "bulwark",
    /// "berserker", "initiate". Always non-null — every user has a class,
    /// even Initiate. Renders on Variant B's top collar (mockup §6
    /// "BULWARK" sample).
    required String characterClassSlug,

    /// `true` when the session crossed a class boundary (the queue carried
    /// a `ClassChangeEvent`). The Discreet variant overrides the dominant
    /// BP hue with brand hot violet AND renders "BULWARK DESPERTOU." as
    /// the d-hero in this case (mockup §6 render rules: "If class change
    /// fired → swap chest hue for `hotViolet` + 'BULWARK DESPERTOU.' as
    /// the d-hero"). Variant A + B render their PR / standard XP slot
    /// regardless — class change does not displace the hue on those.
    required bool isClassChange,

    /// `true` when the session unlocked at least one title. Reserved for
    /// future variants (e.g. "Novo título" eyebrow on Variant B); not
    /// rendered in the current Pass-1 layouts but persisted on the payload
    /// so Pass 3's preview-screen toggle can branch without re-computing.
    required bool hasTitleUnlock,

    /// `true` when the session crossed at least one body-part rank
    /// threshold. Used by Variant A's "anchor PR or rank info" branch
    /// (mockup §6 Variant B render rules: "drop [heroGold] on non-PR
    /// sessions and lead with rank info instead").
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
        final aScore = _prScore(a);
        final bScore = _prScore(b);
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

    return SharePayload(
      tier: tier,
      totalXp: totalXp,
      dominantBodyPart: dominantBp,
      dominantBodyPartRank: dominantRank,
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

/// PR scoring tiebreaker — same `weight × reps` heuristic used by the
/// cinematic choreographer.
double _prScore(PersonalRecord r) {
  final weight = r.value;
  final reps = (r.reps ?? 1).clamp(1, 1 << 20);
  return weight * reps;
}

/// Body-part hue lookup — delegates to [VitalityStateStyles.bodyPartColor]
/// (the canonical app-wide map; §13.3 lock contract). Reading through the
/// single source of truth prevents drift between the share card and every
/// other "per-BP color" surface (stats trend chart, rank rail, weekly plan
/// engagement bars).
Color _bodyPartHue(BodyPart bp) =>
    VitalityStateStyles.bodyPartColor[bp] ?? AppColors.hotViolet;
