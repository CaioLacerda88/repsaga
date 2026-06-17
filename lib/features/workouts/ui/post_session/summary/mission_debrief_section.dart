import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../rpg/domain/body_part_hues.dart';
import '../../../../rpg/models/body_part.dart';
import '../../../../rpg/models/celebration_event.dart';
import '../../../utils/cardio_format.dart';
import '../post_session_state.dart';
import 'mission_debrief_localizations.dart';
import 'widgets/cardio_entry_row.dart';
import 'widgets/lift_row.dart';
import 'widgets/xp_segmented_bar.dart';

/// S2 Mission Debrief composer for the post-session summary panel (Phase
/// 31 Pass 3).
///
/// Fills the post-cinematic real estate above the Share / CONTINUE CTAs
/// with a structural report: top-K lift rows, segmented XP-by-BP bar,
/// per-BP rank delta rows, and a next-target callout pointing to the
/// closest rank-up.
///
/// **Layout (top to bottom):**
///   1. Section eyebrow ("RELATÓRIO DA SESSÃO") — Barlow Condensed 600
///      11sp +0.22em textDim.
///   2. Up to 4 [LiftRow]s (top by XP contribution) + optional
///      "+N more exercises" footer when the total trained count exceeds
///      4.
///   3. [XpSegmentedBar] — proportional segments per BP, hue-coded.
///   4. Per-BP rank delta rows — `Costas · Rank 11 → 12` (rank-up
///      session) or `Costas · Rank 12` (no rank-up).
///   5. Next-target callout — eyebrow + body line pointing to the closest
///      rank-up on the dominant BP.
///
/// **Decoupling Rule 2.** All localized strings come in via
/// [MissionDebriefLocalizations] — the widget never reads
/// `AppLocalizations.of(context)`.
///
/// **Defensive cases:**
///   * `setsCount == 0` is already gated upstream by the empty-session
///     guard — the debrief section never renders in that branch.
///   * Empty `state.topLifts` (impossible if sets exist) collapses the
///     lift table; the bar / deltas / callout still render.
///   * No XP earned on any BP (impossible if `setsCount > 0`) — the bar
///     collapses to 0 height via `XpSegmentedBar`'s defensive branch.
class MissionDebriefSection extends StatelessWidget {
  const MissionDebriefSection({
    super.key,
    required this.localizations,
    required this.state,
    this.classLabel,
    this.distanceUnit = 'km',
    this.locale = 'en',
  });

  /// Display distance unit ("km" / "mi") derived from the profile weight
  /// unit. Drives cardio-row distance + pace formatting via [CardioFormat].
  final String distanceUnit;

  /// Language code for locale-aware cardio distance decimal separators.
  final String locale;

  /// Pre-localized string bundle from the screen layer.
  final MissionDebriefLocalizations localizations;

  /// Snapshot of the post-session state. Reads `topLifts`,
  /// `totalExercisesTrained`, `bpXpDeltas`, `bpRankAfter`, `queueResult`,
  /// `dominantBodyPart`, `dominantXpToNextRank`, `dominantNextRank`,
  /// `bodyPartLabels`, and `totalXpEarned`.
  final PostSessionState state;

  /// Pre-localized character-class label rendered as the right-side accent
  /// of the XP hero block ("+340 XP EARNED · IRON SENTINEL"). `null` for
  /// Initiate (so the accent cleanly omits) or when no class is set.
  /// Caller resolves via `localizedClassCopy(cls, l10n).name` and uppercases
  /// at the call site.
  final String? classLabel;

  @override
  Widget build(BuildContext context) {
    // Sort BPs by XP descending — drives both the bar segment order and
    // the per-BP rank delta row order. Stable order for downstream
    // assertions.
    final sortedBpEntries =
        state.bpXpDeltas.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    // BPs with a fired RankUpEvent in the celebration queue → display
    // arrow grammar in the per-BP delta row.
    final rankedUpBodyParts = <BodyPart>{
      for (final e in state.queueResult.queue)
        if (e is RankUpEvent) e.bodyPart,
    };

    final segments = [
      for (final entry in sortedBpEntries)
        XpBarSegment(
          bodyPart: entry.key,
          hue: BodyPartHues.hueFor(entry.key),
          xp: entry.value,
        ),
    ];

    final remainingMore = state.totalExercisesTrained - state.topLifts.length;
    final showMoreFooter = remainingMore > 0;

    final dominantBp = state.dominantBodyPart;
    final dominantBpLabel = dominantBp == null
        ? null
        : state.bodyPartLabels[dominantBp];
    final showNextTarget =
        dominantBp != null &&
        dominantBpLabel != null &&
        state.dominantXpToNextRank != null &&
        state.dominantNextRank != null;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'mission-debrief-section',
      label: localizations.debriefEyebrow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          // 0) XP hero block (Phase 31 round-2 Bug F).
          //
          // Spec'd by mockup Direction 2 as the FIRST child of the Mission
          // Debrief — "+340 XP EARNED / IRON SENTINEL" framed by a hair
          // divider on its bottom edge. Hides cleanly when no XP was
          // earned (defensive — the section is already gated upstream
          // for sets > 0, but guarding here keeps the widget self-safe).
          if (state.totalXpEarned > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(
                // `AppColors.hair` is the canonical hair-divider color
                // (rgba(179,109,255,0.14) — see `app_theme.dart`). The
                // mockup CSS calls for rgba(179,109,255,0.10) but the
                // hairline difference is below the visual-noise floor
                // and using the canonical token keeps the design system
                // contract intact (no parallel hair-violet variant).
                border: Border(
                  bottom: BorderSide(color: AppColors.hair, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '+${state.totalXpEarned}',
                    style: AppTextStyles.numeric.copyWith(
                      fontSize: 36,
                      letterSpacing: -0.02 * 36,
                      color: AppColors.textCream,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    localizations.xpEarnedLabel.toUpperCase(),
                    style: AppTextStyles.label.copyWith(
                      fontSize: 12,
                      letterSpacing: 0.16 * 12,
                      color: AppColors.textDim,
                    ),
                  ),
                  const Spacer(),
                  if (classLabel != null)
                    Text(
                      classLabel!.toUpperCase(),
                      style: AppTextStyles.label.copyWith(
                        fontSize: 11,
                        letterSpacing: 0.10 * 11,
                        color: AppColors.hotViolet,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          // 1) Section eyebrow.
          Text(
            localizations.debriefEyebrow.toUpperCase(),
            style: AppTextStyles.label.copyWith(
              fontSize: 11,
              letterSpacing: 0.22 * 11,
              color: AppColors.textDim,
            ),
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 12),

          // 2) Lift rows (top 4) — wrapped in identifier per-row.
          for (var i = 0; i < state.topLifts.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Semantics(
              container: true,
              explicitChildNodes: true,
              identifier: 'mission-debrief-lift-row-$i',
              child: LiftRow(
                bodyPartHue: BodyPartHues.hueFor(state.topLifts[i].bodyPart),
                exerciseName: state.topLifts[i].exerciseName,
                peakReps: state.topLifts[i].peakReps,
                peakWeightKg: state.topLifts[i].peakWeightKg,
                prLabel: state.topLifts[i].isPR ? localizations.prFlag : null,
                weightUnitLabel: localizations.weightUnit,
              ),
            ),
          ],

          // Cardio rows (Phase 38e) — rendered in the SAME ledger, after the
          // strength lift rows, so a mixed session reads coherent. Sourced
          // from `state.cardioEntries` (completed cardio entries), NOT from
          // `topLifts` (cardio earns no strength-XP delta). No PR / heroGold.
          for (var i = 0; i < state.cardioEntries.length; i++) ...[
            if (i > 0 || state.topLifts.isNotEmpty) const SizedBox(height: 8),
            Semantics(
              container: true,
              explicitChildNodes: true,
              identifier: 'mission-debrief-cardio-row-$i',
              child: CardioEntryRow(
                activityName: state.cardioEntries[i].activityName,
                durationLabel: CardioFormat.duration(
                  state.cardioEntries[i].durationSeconds,
                ),
                distanceSuffix: state.cardioEntries[i].distanceM == null
                    ? null
                    : '${CardioFormat.distanceValue(state.cardioEntries[i].distanceM!, distanceUnit: distanceUnit, locale: locale)} $distanceUnit',
                paceSuffix: state.cardioEntries[i].paceSecondsPerKm == null
                    ? null
                    : CardioFormat.pace(
                        state.cardioEntries[i].paceSecondsPerKm!,
                        distanceUnit: distanceUnit,
                      ),
              ),
            ),
          ],

          if (showMoreFooter) ...[
            const SizedBox(height: 6),
            Text(
              localizations.moreLifts(remainingMore),
              textAlign: TextAlign.center,
              style: AppTextStyles.label.copyWith(
                fontSize: 11,
                letterSpacing: 0.20 * 11,
                color: AppColors.textDim,
              ),
            ),
          ],
          const SizedBox(height: 16),

          // 3) Segmented XP bar.
          if (segments.isNotEmpty) XpSegmentedBar(segments: segments),
          if (segments.isNotEmpty) const SizedBox(height: 16),

          // 4) Per-BP rank delta rows.
          for (var i = 0; i < sortedBpEntries.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _BpRankDeltaRow(
              bodyPart: sortedBpEntries[i].key,
              bodyPartLabel:
                  state.bodyPartLabels[sortedBpEntries[i].key] ??
                  sortedBpEntries[i].key.dbValue,
              rankAfter: state.bpRankAfter[sortedBpEntries[i].key] ?? 1,
              // Blocker 1 — use the persisted pre-session rank instead of
              // `rankAfter - 1`. Multi-rank-jump sessions (e.g. 5 → 8) need
              // the true `from` endpoint, not a one-off decrement.
              rankBefore:
                  state.bpRankBefore[sortedBpEntries[i].key] ??
                  ((state.bpRankAfter[sortedBpEntries[i].key] ?? 1) - 1).clamp(
                    1,
                    999,
                  ),
              didRankUp: rankedUpBodyParts.contains(sortedBpEntries[i].key),
              rankLabel: localizations.rankLabel,
              rankUpArrow: localizations.rankUpArrow,
            ),
          ],
          // Spacing + structural divider before the next-target callout
          // (Phase 31 round-2 Bug G). The mockup Direction 2 spec'd a hair
          // divider between the rank-delta rows and the "PRÓXIMO PASSO"
          // eyebrow so the callout reads as its own structural block, not
          // a continuation of the deltas. 16 → 20 dp gap above the rule,
          // 10 dp gap below.
          if (sortedBpEntries.isNotEmpty) const SizedBox(height: 20),

          // 5) Next-target callout.
          if (showNextTarget) ...[
            const Divider(color: AppColors.hair, height: 1, thickness: 1),
            const SizedBox(height: 10),
            Text(
              localizations.nextTargetEyebrow.toUpperCase(),
              textAlign: TextAlign.left,
              style: AppTextStyles.label.copyWith(
                fontSize: 11,
                letterSpacing: 0.22 * 11,
                color: AppColors.primaryViolet,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              localizations.nextTargetBody(
                state.dominantXpToNextRank!,
                dominantBpLabel,
                state.dominantNextRank!,
              ),
              style: AppTextStyles.body.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// One per-BP rank delta row. Renders either "{BP} · Rank N → M"
/// (rank-up session — `N` and `M` may differ by more than 1 on multi-rank-
/// jump sessions) or "{BP} · Rank N" (no rank-up). Hue tints the BP label.
class _BpRankDeltaRow extends StatelessWidget {
  const _BpRankDeltaRow({
    required this.bodyPart,
    required this.bodyPartLabel,
    required this.didRankUp,
    required this.rankBefore,
    required this.rankAfter,
    required this.rankLabel,
    required this.rankUpArrow,
  });

  final BodyPart bodyPart;
  final String bodyPartLabel;
  final bool didRankUp;
  final int rankBefore;
  final int rankAfter;
  final String Function(int rank) rankLabel;
  final String Function(int from, int to) rankUpArrow;

  @override
  Widget build(BuildContext context) {
    final hue = BodyPartHues.hueFor(bodyPart);
    final rankText = didRankUp
        ? rankUpArrow(rankBefore, rankAfter)
        : rankLabel(rankAfter);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'mission-debrief-bp-row-${bodyPart.dbValue}',
      label: '$bodyPartLabel · $rankText',
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: bodyPartLabel,
              style: AppTextStyles.label.copyWith(
                fontSize: 13,
                letterSpacing: 0,
                color: hue,
              ),
            ),
            TextSpan(
              text: '  ·  ',
              style: AppTextStyles.label.copyWith(
                color: AppColors.textDim,
                letterSpacing: 0,
              ),
            ),
            TextSpan(
              text: rankText,
              style: AppTextStyles.numeric.copyWith(
                fontSize: 13,
                color: AppColors.textCream,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
