import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../rpg/models/body_part.dart';
import '../../../../rpg/ui/utils/vitality_state_styles.dart';
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
    required this.shareComingSoonMessage,
    required this.onContinue,
    this.hasShareCta = false,
    this.titleEquipRow,
    this.rankUpOverflow,
    this.prDetailRow,
    this.classChangeRow,
    this.nextStepHookFormatter,
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

  /// "CONTINUAR ▶" label.
  final String continueLabel;

  /// "📷 Compartilhar saga" label (30a placeholder).
  final String shareLabel;

  /// "Em breve" snackbar message.
  final String shareComingSoonMessage;

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

  /// Optional PR detail row (mockup §5 State 3 — "Supino · 95kg × 5,
  /// +5kg vs anterior.").
  final Widget? prDetailRow;

  /// Optional class-change badge row (mockup §5 State 9 + 10).
  final Widget? classChangeRow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'post-session-summary',
      label: 'Post-session summary · $sagaLabel',
      child: ColoredBox(
        color: AppColors.abyss,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  sagaLabel,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.textDim,
                    fontSize: 12,
                  ),
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
                if (nextStepHook != null) ...[
                  const SizedBox(height: 18),
                  const Divider(color: AppColors.hair, height: 1),
                  const SizedBox(height: 10),
                  Text(
                    nextStepEyebrow.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.hotViolet,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatHook(nextStepHook!),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body,
                  ),
                ],
                if (prDetailRow != null) ...[
                  const SizedBox(height: 14),
                  prDetailRow!,
                ],
                if (classChangeRow != null) ...[
                  const SizedBox(height: 14),
                  classChangeRow!,
                ],
                if (rankUpOverflow != null) ...[
                  const SizedBox(height: 14),
                  rankUpOverflow!,
                ],
                if (titleEquipRow != null) ...[
                  const SizedBox(height: 14),
                  titleEquipRow!,
                ],
                const Spacer(),
                if (hasShareCta) ...[
                  ShareCtaButton(
                    label: shareLabel,
                    comingSoonMessage: shareComingSoonMessage,
                  ),
                  const SizedBox(height: 10),
                ],
                Semantics(
                  container: true,
                  explicitChildNodes: true,
                  identifier: 'post-session-continue-cta',
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onContinue,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryViolet,
                        foregroundColor: AppColors.textCream,
                      ),
                      child: Text(continueLabel),
                    ),
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
