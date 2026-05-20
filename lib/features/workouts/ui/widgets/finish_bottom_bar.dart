import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';

/// Persistent bottom bar hosting the "Finish workout" action.
///
/// BUG-020: previously rendered as an AppBar trailing OutlinedButton (Phase
/// 18c §13). Moved here so the action is reachable one-handed and discoverable
/// to first-time users. The [FinishWorkoutDialog] (gated by [onPressed]) is
/// the safety net — placement is no longer the gate.
///
/// **Decision: REPLACE, not AUGMENT.** The AppBar Finish was removed entirely
/// when this bar landed. Two CTAs for the same action would be UI noise and
/// would split the loading/disabled state machine across two surfaces — single
/// source of truth (this widget's [enabled] gate + [onPressed] backed by
/// [FinishWorkoutCoordinator]) is cleaner. AppBar now hosts only the discard
/// leading + reorder action — see `active_workout_screen.dart`. Phase 20
/// commit 5 ratifies this decision.
///
/// Styling: filled primaryViolet button (Cluster 4 review — was OutlinedButton,
/// which read as a secondary action despite being THE next-step CTA). 56dp min
/// height — Phase 20 spec requires ≥56dp to match Hevy/Strong's chunky
/// bottom-bar CTAs and give a generous one-handed thumb target. Full-width
/// minus 16dp horizontal padding. Top divider uses the canonical
/// [AppColors.hair] token (Cluster 4 review — was
/// `outline.withValues(alpha: 0.2)`, which composited to ~2.8% effective alpha
/// on top of the already 14%-alpha hair token, making the line invisible).
/// SafeArea handles gesture insets on iOS / Android-with-bottom-bar.
///
/// **Selector contract:** the outer [Material] carries
/// `ValueKey('finish-bottom-bar')` and a `Semantics(identifier:
/// 'workout-finish-btn')` wraps the button. Both are E2E selector contracts
/// (see `test/e2e/helpers/selectors.ts` `WORKOUT.finishButton` and the
/// `test/widget/.../active_workout_finish_button_test.dart` pin) — do not
/// rename without updating both call sites.
class FinishBottomBar extends StatelessWidget {
  const FinishBottomBar({
    required this.enabled,
    required this.onPressed,
    super.key,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      key: const ValueKey('finish-bottom-bar'),
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.hair, width: 1)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          // Pair-rule: every Semantics(identifier:) we expose for e2e MUST
          // set BOTH container AND explicitChildNodes (PR #152 lessons.md
          // entry). Without explicitChildNodes the FilledButton's own
          // semantics + the Text label can be merged with sibling Semantics
          // in the surrounding Column / Material tree, which is what caused
          // the PR #152 e2e regressions on row-level identifiers.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                container: true,
                explicitChildNodes: true,
                identifier: 'workout-finish-btn',
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: enabled ? onPressed : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryViolet,
                      foregroundColor: AppColors.textCream,
                      // Disabled state: dim the violet to ~30% so the bar reads as
                      // "intentionally unavailable" rather than broken. Foreground
                      // (textDim) keeps AA contrast against the dimmed background.
                      disabledBackgroundColor: AppColors.primaryViolet
                          .withValues(alpha: 0.3),
                      disabledForegroundColor: AppColors.textDim,
                      minimumSize: const Size(0, 56),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      AppLocalizations.of(context).finishButtonLabel,
                      style: AppTextStyles.headline.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        // headline encodes 0.02em tracking; the Finish CTA wants
                        // tighter chip-style 0.04em tracking — kept explicitly.
                        letterSpacing: 0.04 * 13,
                        color: enabled
                            ? AppColors.textCream
                            : AppColors.textDim,
                      ),
                    ),
                  ),
                ),
              ),
              // PR-5 H6 — explain WHY the button is disabled.
              //
              // Pre-fix a new user with all set values entered but none ticked
              // saw a grey FINISH button and no signal to tap the
              // completion checkboxes. Adding a single line of helper text
              // beneath the button gives the user a concrete action to
              // unblock themselves without consulting docs.
              //
              // Wrapped in `Semantics(identifier: 'finish-disabled-hint')`
              // so E2E can target the helper text directly (selectors.ts
              // `WORKOUT.finishDisabledHint`). Pair-rule
              // (`container: true` + `explicitChildNodes: true`) applies
              // because we expose an identifier for E2E.
              if (!enabled)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    identifier: 'finish-disabled-hint',
                    child: Text(
                      AppLocalizations.of(context).finishWorkoutDisabledHint,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
