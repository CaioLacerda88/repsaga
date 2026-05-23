import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// User's choice when the empty-session guard sheet is presented.
///
/// Returned by [EmptySessionGuardSheet.show] so the caller can branch on
/// "discard the workout entirely" vs "go back to logging sets". Cancelling
/// the sheet (back press / barrier tap) returns [cancelled] — same
/// semantics as "Continuar treinando" (preserve the workout).
enum EmptySessionGuardResult {
  /// User tapped "Descartar" — discard the workout, navigate home.
  discarded,

  /// User tapped "Continuar treinando" — keep the workout open.
  continueTraining,

  /// Sheet was dismissed via back press / barrier tap. Treated as
  /// continueTraining by the coordinator (default to non-destructive).
  cancelled,
}

/// Modal guard for State 11 (mockup §5) — fires when the user taps
/// "Finish workout" with zero sets logged.
///
/// **Why a guard at the coordinator layer + a modal sheet** (mockup §5
/// State 11 script + WIP.md PR 30a acceptance #3): playing the post-session
/// cinematic for zero work would train users that the RPG layer is fake.
/// The screen never fires; the user picks one of two destinations.
///
/// **Decoupling Rule 2 — localized strings injected as props.** The sheet
/// renders strings supplied by the caller (typically the coordinator
/// reading `AppLocalizations`), keeping this widget unit-testable without
/// an l10n harness.
class EmptySessionGuardSheet extends StatelessWidget {
  const EmptySessionGuardSheet({
    super.key,
    required this.title,
    required this.body,
    required this.discardLabel,
    required this.continueLabel,
  });

  final String title;
  final String body;
  final String discardLabel;
  final String continueLabel;

  /// Open the sheet against [context] and return the user's choice.
  ///
  /// Uses `showModalBottomSheet` so the active-workout screen stays
  /// visible behind a barrier — the user knows what they're cancelling.
  /// Returns [EmptySessionGuardResult.cancelled] when dismissed via
  /// back press or barrier tap.
  static Future<EmptySessionGuardResult> show(
    BuildContext context, {
    required String title,
    required String body,
    required String discardLabel,
    required String continueLabel,
  }) async {
    final result = await showModalBottomSheet<EmptySessionGuardResult>(
      context: context,
      backgroundColor: AppColors.surface,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) {
        return EmptySessionGuardSheet(
          title: title,
          body: body,
          discardLabel: discardLabel,
          continueLabel: continueLabel,
        );
      },
    );
    return result ?? EmptySessionGuardResult.cancelled;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'empty-session-guard-sheet',
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.hotViolet,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                body,
                textAlign: TextAlign.center,
                style: AppTextStyles.body,
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(EmptySessionGuardResult.continueTraining),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryViolet,
                  foregroundColor: AppColors.textCream,
                ),
                child: Text(continueLabel),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(EmptySessionGuardResult.discarded),
                style: TextButton.styleFrom(foregroundColor: AppColors.textDim),
                child: Text(discardLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
