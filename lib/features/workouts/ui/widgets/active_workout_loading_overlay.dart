import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../providers/workout_providers.dart';

/// Loading overlay shown during async operations (start/finish/discard).
///
/// **Q1 (PR1) — always-visible Cancel.** Pre-PR1 the Cancel button was
/// hidden behind a 10s timer AND a `hasRestorable` boolean gate. Both were
/// removed once C4 made `cancelLoading()` always do something useful:
///
///   * If a prior valid state exists, restore it (mid-workout cancel).
///   * Otherwise emit `AsyncData(null)` so the active-workout screen
///     navigates back to /home (start-phase cancel).
///
/// With the no-op case eliminated, the affordance is safe to render
/// immediately — it always has a meaningful action and never traps the
/// user. Removing the timer also avoids the dual user-hostile failure
/// modes of "wait 10s before you can escape a stuck network" and "the
/// button appearing pushes users to abort fast saves on slow networks".
class ActiveWorkoutLoadingOverlay extends ConsumerWidget {
  const ActiveWorkoutLoadingOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        // Scrim over the active-workout surface while the overlay loads.
        // abyss (#0D0319) at ~54% alpha as the dim-out layer.
        ModalBarrier(
          dismissible: false,
          color: AppColors.abyss.withValues(alpha: 0.54),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () {
                  ref.read(activeWorkoutProvider.notifier).cancelLoading();
                },
                // PR-7 (UI-critic deferred from PR-1): scoped `loadingOverlayStop`
                // key replaces the generic `cancel` key. "Cancel" on the
                // spinner during a finish/discard flow reads as "cancel my
                // workout" — i.e. discard the entire session — when the
                // intent is only to abort the in-flight save/discard
                // request and restore the prior state. "Stop" / "Parar" is
                // unambiguous about what gets stopped.
                child: Text(
                  AppLocalizations.of(context).loadingOverlayStop,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
