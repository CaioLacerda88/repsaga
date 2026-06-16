import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../rpg/models/body_part.dart';
import '../../../../rpg/ui/utils/vitality_state_styles.dart';
import '../../../domain/share_payload.dart';
import '../share/share_card_renderer.dart';
import '../share/share_localizations.dart';
import 'next_step_hook.dart';
import 'share_cta_button.dart';

/// Composition of small widgets that make up the post-session summary
/// panel (Decoupling Rule 5).
///
/// **Decoupling Rule 2 — every localized string is injected as a prop.**
/// The screen layer resolves ARB keys and supplies already-localized
/// strings. This widget renders layout only.
///
/// Each row is conditional on the presence of its payload — see the
/// per-state script in mockup §5 for the visibility rules.
///
/// **Visual contract (mockup §5 final frames, locked 2026-05-23):**
///   * Saga eyebrow at top in [AppTextStyles.label] textDim (11sp Barlow
///     Condensed tracked) — matches mockup `t-label` register.
///   * Duration/sets numeric in [AppTextStyles.numeric] at 17sp (Rajdhani
///     700 tabular) — matches mockup `t-numeric` register.
///   * Tonnage caption in [AppTextStyles.bodySmall] (Barlow 12sp textDim) —
///     matches mockup `t-body-sm` register.
///   * Hair divider above the next-step hook (`AppColors.hair`).
///   * Next-step eyebrow color comes from [nextStepEyebrowColor] (mockup
///     §5 uses hotViolet / heroGold / bp-* per state).
///   * Share CTA and CONTINUE rendered via [_PostSessionCinematicButton] —
///     Rajdhani 600 11sp tracked label + leading/trailing Material icon,
///     never an emoji glyph in the text (jarring against the Concept B
///     palette per the 2026-05-23 visual gate).
///   * Outer SafeArea uses `minimum: EdgeInsets.only(top: 12, bottom: 16)`
///     to guarantee a padding floor on devices (Samsung floating-pill
///     gesture nav) that report 0 inset for the bottom system region
///     while still rendering a pill that visually overlaps content.
class PostSessionSummaryPanel extends StatelessWidget {
  const PostSessionSummaryPanel({
    super.key,
    required this.sagaLabel,
    required this.durationSetsLabel,
    required this.tonnageLabel,
    required this.nextStepEyebrow,
    required this.nextStepHook,
    required this.continueLabel,
    required this.shareLabel,
    required this.onContinue,
    this.sharePayload,
    this.shareCardStrings,
    this.shareLocalizations,
    this.hasShareCta = false,
    this.titleEquipRow,
    this.rankUpOverflow,
    this.debriefSection,
    this.nextStepHookFormatter,
    this.nextStepEyebrowColor,
    this.agePrompt,
  });

  /// "Saga 47" or "1ª saga" (day-zero variant). Pre-resolved.
  final String sagaLabel;

  /// "{minutes} min · {sets} séries" already formatted.
  final String durationSetsLabel;

  /// "{kg} ton" already formatted.
  final String tonnageLabel;

  /// "Próximo passo" eyebrow (pre-localized).
  final String nextStepEyebrow;

  /// Discriminated hook variant. The screen layer supplies an optional
  /// [nextStepHookFormatter] that knows how to render each variant into
  /// a single string (since the strings need to interpolate values plus
  /// localized templates).
  final NextStepHookKind? nextStepHook;

  /// Optional pre-formatted text resolver for [nextStepHook]. If null,
  /// a generic fallback renders the hook payload as a debug string.
  final String Function(NextStepHookKind hook)? nextStepHookFormatter;

  /// Accent color for the next-step eyebrow (mockup §5 per-state palette
  /// — hotViolet for baseline / level-up, heroGold for PR detail, BP hue
  /// for rank-up / title states). Defaults to [AppColors.hotViolet] when
  /// the screen layer doesn't override.
  final Color? nextStepEyebrowColor;

  /// "CONTINUAR" label (no glyph baked in — the arrow icon renders
  /// separately at the call site).
  final String continueLabel;

  /// "Compartilhar saga" label (no glyph baked in — the camera icon
  /// renders separately at the call site).
  final String shareLabel;

  /// Pre-composed share payload, sourced from `PostSessionState` by the
  /// screen layer. Required when [hasShareCta] is true. Null when the
  /// CTA is hidden (baseline / day-zero / level-up only).
  final SharePayload? sharePayload;

  /// Pre-localized share-card overlay strings. Required when
  /// [hasShareCta] is true.
  final ShareCardStrings? shareCardStrings;

  /// Pre-localized share-sheet + preview-screen labels. Required when
  /// [hasShareCta] is true.
  final ShareLocalizations? shareLocalizations;

  /// Called when the user taps CONTINUAR. Route-agnostic per Decoupling
  /// Rule 8 — the route container wires this to GoRouter.
  final VoidCallback onContinue;

  /// Show the share CTA. True when the queue contains any of PR / rank-up /
  /// title / class-change per WIP.md PR 30a Open question #5.
  final bool hasShareCta;

  /// Optional title EQUIP row when a title was unlocked this session.
  final Widget? titleEquipRow;

  /// Optional overflow card for multi-rank-up state (mockup §5 State 6).
  final Widget? rankUpOverflow;

  /// Optional S2 Mission Debrief section (Phase 31 Pass 3). Renders below
  /// the duration/tonnage block — surfaces named lift rows, segmented XP
  /// bar, per-BP rank deltas, and the next-target callout. When supplied,
  /// the panel's separate next-step eyebrow+hook block (the legacy
  /// summaryNextStepLabel + summaryNextRank/Level pair) is hidden because
  /// the debrief section's next-target callout subsumes it.
  final Widget? debriefSection;

  /// Phase 38d — optional one-time "set your age" nudge. Supplied by the
  /// screen layer only when the finished session had a completed cardio
  /// entry, the user has no birth date on file, and the prompt hasn't been
  /// dismissed. Renders directly under the summary metrics block (mockup
  /// §5/§6 — a slim in-context banner, not a modal).
  final Widget? agePrompt;

  @override
  Widget build(BuildContext context) {
    final eyebrowColor = nextStepEyebrowColor ?? AppColors.hotViolet;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'post-session-summary',
      label: 'Post-session summary · $sagaLabel',
      child: ColoredBox(
        color: AppColors.abyss,
        child: SafeArea(
          // `minimum` guarantees a padding floor for the gesture-nav region
          // on Samsung devices whose floating pill design reports
          // `MediaQuery.padding.bottom == 0` while still rendering a visible
          // indicator that would otherwise overlap CONTINUE. The Galaxy S25
          // Ultra visual-gate run (2026-05-23) surfaced the regression.
          minimum: const EdgeInsets.only(top: 12, bottom: 16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Saga eyebrow — mockup `t-label` register (Barlow Condensed
                // 11sp tracked) in textDim. The number stays visually quiet
                // here because the cinematic preceding the summary already
                // carried the saga's emotional weight via B1/B2/B3 cuts.
                Text(
                  sagaLabel,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.label.copyWith(color: AppColors.textDim),
                ),
                const SizedBox(height: 16),
                Text(
                  durationSetsLabel,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.numeric.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  tonnageLabel,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall,
                ),
                // Legacy next-step eyebrow+hook block. Only renders when
                // the Phase 31 debrief section isn't supplied — the
                // debrief subsumes the next-target callout via its
                // fifth row. The fallback exists for fixtures that don't
                // wire the debrief (tests of the panel chrome, day-zero
                // baselines, etc).
                if (debriefSection == null && nextStepHook != null) ...[
                  const SizedBox(height: 22),
                  const Divider(color: AppColors.hair, height: 1),
                  const SizedBox(height: 10),
                  Text(
                    nextStepEyebrow.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.label.copyWith(
                      color: eyebrowColor,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatHook(nextStepHook!),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body,
                  ),
                ],
                if (rankUpOverflow != null) ...[
                  const SizedBox(height: 14),
                  rankUpOverflow!,
                ],
                if (titleEquipRow != null) ...[
                  const SizedBox(height: 14),
                  titleEquipRow!,
                ],
                if (debriefSection != null) ...[
                  const SizedBox(height: 8),
                  debriefSection!,
                ],
                ?agePrompt,
                const Spacer(),
                if (hasShareCta &&
                    sharePayload != null &&
                    shareCardStrings != null &&
                    shareLocalizations != null) ...[
                  ShareCtaButton(
                    label: shareLabel,
                    payload: sharePayload!,
                    strings: shareCardStrings!,
                    l10n: shareLocalizations!,
                  ),
                  const SizedBox(height: 10),
                ],
                Semantics(
                  container: true,
                  explicitChildNodes: true,
                  identifier: 'post-session-continue-cta',
                  child: PostSessionCinematicButton(
                    label: continueLabel,
                    backgroundColor: AppColors.primaryViolet,
                    foregroundColor: AppColors.textCream,
                    trailingIcon: Icons.arrow_forward_rounded,
                    onPressed: onContinue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatHook(NextStepHookKind hook) {
    if (nextStepHookFormatter != null) return nextStepHookFormatter!(hook);
    // Defensive fallback — the screen layer should ALWAYS provide a
    // formatter. The debug string here makes the missing formatter
    // visible in development rather than silently dropping copy.
    return switch (hook) {
      NextRankHook(:final bodyPart, :final xpToNextRank, :final nextRank) =>
        '$xpToNextRank XP → ${bodyPart.dbValue} rank $nextRank',
      NextLevelHook(:final ranksToNextLevel, :final nextLevel) =>
        '$ranksToNextLevel ranks → level $nextLevel',
      PrDetailHook(
        :final exerciseName,
        :final weightKg,
        :final reps,
        :final improvementKg,
      ) =>
        '$exerciseName · ${weightKg}kg × $reps (+${improvementKg}kg)',
    };
  }
}

/// Concept B finisher button — Rajdhani 600 11sp tracked label, hard-edged
/// rectangle (`kRadiusSm = 4`), with an optional leading/trailing Material
/// icon at the same color as the label.
///
/// Used for both the Share CTA and CONTINUE on the post-session summary.
/// Deliberately NOT a `FilledButton` because the app-wide
/// [AppTheme.filledButtonTheme] renders Barlow Condensed labels with rounded
/// corners — appropriate for general app surfaces but mismatched with the
/// cinematic-finisher grammar mockup §5 specifies (Rajdhani-display family,
/// `kRadiusXs` square edges, `padding: 6px vertical`).
///
/// **Selector contract:** the button is an `InkWell` inside a `Material` —
/// `tester.tap(find.byType(PostSessionCinematicButton))` works in widget
/// tests; the parent `Semantics(identifier:)` injected by the panel keeps
/// the E2E selector contract.
class PostSessionCinematicButton extends StatelessWidget {
  const PostSessionCinematicButton({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;
  final IconData? leadingIcon;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      // Square-ish corners per mockup `.continue-btn-cut` (border-radius: 4).
      // Matches `kRadiusSm` but inlined as a literal here because the
      // Concept B grammar treats hard edges as load-bearing — not a generic
      // app rounding that should drift with the radii scale.
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, color: foregroundColor, size: 16),
                const SizedBox(width: 8),
              ],
              Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                // Concept B finisher type — Rajdhani 600 13sp tracked at
                // 0.04em per mockup `.continue-btn-cut`. Derived from
                // [AppTextStyles.titleDisplay] (Rajdhani 600) with the
                // tracked-button overrides applied; routes through the
                // sanctioned token so the typography-call-sites gate
                // stays clean instead of falling back to a raw
                // `fontFamily: 'Rajdhani'` literal.
                style: AppTextStyles.titleDisplay.copyWith(
                  fontSize: 13,
                  letterSpacing: 0.04 * 13,
                  height: 1.2,
                  color: foregroundColor,
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 8),
                Icon(trailingIcon, color: foregroundColor, size: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact body part rank-up overflow row for mockup §5 State 6.
/// Renders as a "▲ {bodyPart} · RANK {n}" pill inside a tinted background.
class RankUpOverflowRow extends StatelessWidget {
  const RankUpOverflowRow({
    super.key,
    required this.bodyPart,
    required this.bodyPartLabel,
    required this.newRank,
    required this.headerLabel,
  });

  final BodyPart bodyPart;
  final String bodyPartLabel;
  final int newRank;
  final String headerLabel;

  @override
  Widget build(BuildContext context) {
    final hue =
        VitalityStateStyles.bodyPartColor[bodyPart] ?? AppColors.hotViolet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          headerLabel.toUpperCase(),
          textAlign: TextAlign.center,
          style: AppTextStyles.label.copyWith(
            color: AppColors.hotViolet,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: hue.withValues(alpha: 0.10),
          child: Row(
            children: [
              Text(
                '▲ ${bodyPartLabel.toUpperCase()}',
                style: AppTextStyles.label.copyWith(color: hue, fontSize: 11),
              ),
              const Spacer(),
              Text(
                'RANK $newRank',
                style: AppTextStyles.numericSmall.copyWith(
                  color: AppColors.textCream,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
