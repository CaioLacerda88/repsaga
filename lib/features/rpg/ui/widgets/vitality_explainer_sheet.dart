import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/reward_accent.dart';

/// Bottom-sheet content for the vitality explainer (Phase 26c).
///
/// Triggered by the ⓘ icon on either vitality section header (the trend
/// chart's heading and the live-vitality table's heading in
/// `StatsDeepDiveScreen`). Same content from both entry points. Three
/// sections:
///
///   1. **Definition** — what Vitality measures.
///   2. **Three-state band ramp** — Active / Waning / Dormant with their
///      percentage ranges and one-line copy. Colors consume the Phase 26a
///      `AppColors.vitalityHigh/Mid/Low` aliases.
///   3. **Rank-safety guarantee** — heroGold-bordered box stating that
///      Vitality does NOT affect rank or XP. heroGold rendering flows
///      through `RewardAccent` per the scarcity contract.
///
/// To open from a parent widget, use `showModalBottomSheet`:
///
/// ```dart
/// showModalBottomSheet<void>(
///   context: context,
///   isScrollControlled: true,
///   backgroundColor: Colors.transparent,
///   builder: (_) => const VitalityExplainerSheet(),
/// );
/// ```
///
/// Spec source: docs/PROJECT.md §3 Phase 26 → 26c acceptance criteria.
/// Visual reference: docs/phase-26-mockups.html section `#vitality-explainer`.
class VitalityExplainerSheet extends StatelessWidget {
  const VitalityExplainerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      identifier: 'vitality-explainer-sheet',
      label: l10n.vitalityExplainerTitle,
      child: DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.40,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(kRadiusLg),
            ),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              // Sheet handle (drag affordance — visual only since the
              // DraggableScrollableSheet itself handles the gesture).
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textDim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.vitalityExplainerTitle,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.vitalityExplainerDefinition,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.vitalityExplainerHowItMoves,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _BandRow(
                color: AppColors.vitalityHigh,
                copy: l10n.vitalityExplainerBandActive,
              ),
              const SizedBox(height: 6),
              _BandRow(
                color: AppColors.vitalityMid,
                copy: l10n.vitalityExplainerBandWaning,
              ),
              const SizedBox(height: 6),
              _BandRow(
                color: AppColors.vitalityLow,
                copy: l10n.vitalityExplainerBandDormant,
              ),
              const SizedBox(height: 20),
              // heroGold-bordered rank-safety box. RewardAccent wraps so
              // the gold rendering flows through the scarcity-rule
              // contract (see lib/shared/widgets/reward_accent.dart +
              // scripts/check_reward_accent.sh whitelist).
              RewardAccent(
                child: Builder(
                  builder: (context) {
                    final gold = RewardAccent.of(context)!.color;
                    return DecoratedBox(
                      key: const ValueKey('vitality-explainer-rank-safety-box'),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(kRadiusMd),
                        border: Border.all(color: gold, width: 1),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          l10n.vitalityExplainerRankSafety,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: gold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BandRow extends StatelessWidget {
  const _BandRow({required this.color, required this.copy});

  final Color color;
  final String copy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(copy, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}
