import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/connectivity/connectivity_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../routines/models/routine.dart';
import '../../../routines/providers/notifiers/routine_list_notifier.dart';
import '../../../routines/ui/start_routine_action.dart';
import '../../../weekly_plan/data/models/weekly_plan.dart';
import '../../../weekly_plan/providers/suggested_next_provider.dart';
import '../../../weekly_plan/utils/routine_duration_estimator.dart';
import '../../providers/workout_history_providers.dart';
import '../../providers/workout_providers.dart';
import 'resume_workout_dialog.dart';

/// The banner CTA on the Home screen.
///
/// Phase 26f collapsed the legacy 4-branch state machine (active /
/// brand-new / lapsed / week-complete) into 3 deterministic branches keyed
/// off the user's workout history + bucket state:
///
/// 1. **Day-0 user with no custom routines** (`workoutCountProvider == 0`
///    AND no user-owned routine exists) → `_CreateFirstRoutineHero` points
///    the user at `/routines/create`. Preserves the legacy `_BrandNewHero`
///    semantics — default routines ship seeded for every user, so the gate
///    explicitly filters them out with the same `!r.isDefault` filter
///    `_HomeRoutinesList` uses. "Has the user ever lifted?" is the real
///    onboarding signal, AND "has the user already built a routine?" is the
///    de-duplication guard so the day-0 CTA doesn't redundantly tell a
///    routine-having user to go create one (Phase 27 L3 fix —
///    `_DefaultRoutinesPreview` shows the seeded starter kit on the routines
///    surface; this hero owns the create-routine call-to-action only when
///    the user genuinely has no routine yet). L1 fix (visual verification,
///    2026-05-18) introduced the workout-count gate; L3 (2026-05-19)
///    tightened it with the user-routine check.
/// 2. **Bucket has an uncompleted entry** (`suggestedNextProvider != null`)
///    → `_StartNextRoutineHero` shows `Iniciar {routineName}` and starts
///    the routine on tap (resume-vs-start guard preserved via
///    [startRoutineWorkout]).
/// 3. **Otherwise** → `_FreeWorkoutHero` surfaces the spontaneous "free
///    workout" entry point. When `isWeekCompleteProvider` is true the
///    subline reads "Semana completa"; otherwise the slot is empty so the
///    layout stays stable.
///
/// **Outer semantics wrapper.** Every branch sits inside an outer
/// `Semantics(identifier: 'home-action-hero', container: true,
/// explicitChildNodes: true)` so charter E2E specs that just assert "hero
/// exists" keep working across all 3 states. Each branch ALSO sets its own
/// per-branch identifier (`home-action-hero-start-routine`,
/// `home-action-hero-free-workout`,
/// `home-action-hero-create-first-routine`) so flow-specific specs target
/// the variant without locale-dependent text. Decision locked 2026-05-18.
///
/// **Why scoped per-branch widgets.** Each ConsumerWidget owns the
/// providers it actually needs. Outer ActionHero only watches
/// [workoutCountProvider] (the day-0 gate); per-branch subscriptions (e.g.
/// resolving the routine name for "Iniciar X" via [routineListProvider])
/// stay inside the relevant branch so we don't rebuild the whole hero when
/// the non-active branch's data churns.
class ActionHero extends ConsumerWidget {
  const ActionHero({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Day-0 gate: user has never recorded a workout. `workoutCountProvider`
    // is `keepAlive` and is awaited by the Phase-27 `homeReadyProvider`
    // gate in HomeScreen — in production this `.value` is always
    // non-null on first paint (HomeScreen holds the skeleton until the
    // four critical providers resolve, including this one). The `?? 0`
    // default survives as a safety net for tests that render this widget
    // outside the gate; in production it's dead code.
    final workoutCount = ref.watch(workoutCountProvider).value ?? 0;

    // L3 tightening (Phase 27, 2026-05-19): also gate on "user hasn't built
    // a routine yet". Same `!r.isDefault` filter used by `_HomeRoutinesList`
    // — seeded default routines don't count as user-built. Like
    // `workoutCount` above, the `homeReadyProvider` gate makes the `??`
    // fallback dead code in production; it's preserved for direct-widget
    // tests that don't construct the full HomeScreen tree.
    final userRoutines =
        ref
            .watch(routineListProvider)
            .value
            ?.where((r) => r.userId != null && !r.isDefault)
            .toList() ??
        const <Routine>[];

    final Widget branch;
    if (workoutCount == 0 && userRoutines.isEmpty) {
      branch = const _CreateFirstRoutineHero();
    } else {
      final next = ref.watch(suggestedNextProvider);
      if (next != null) {
        branch = _StartNextRoutineHero(bucketEntry: next);
      } else {
        final weekComplete = ref.watch(isWeekCompleteProvider);
        branch = _FreeWorkoutHero(weekComplete: weekComplete);
      }
    }

    // Outer semantics wrapper preserves the stable `home-action-hero`
    // identifier across all three branches. `container: true +
    // explicitChildNodes: true` follows the `semantics-identifier-pair-rule`
    // cluster — the outer node owns the identifier, inner nodes own their
    // own taps/labels.
    return Semantics(
      identifier: 'home-action-hero',
      container: true,
      explicitChildNodes: true,
      child: branch,
    );
  }
}

/// Starts an empty workout with the active-workout resume dialog guard.
///
/// Lifted from the legacy `ActionHero._startQuickWorkout` instance method
/// into a top-level helper so `_FreeWorkoutHero` (which is the only caller
/// post-26f) can invoke it without re-implementing the resume-vs-start
/// branch. Kept identical in behavior:
///
/// * **Offline** — show a snackbar, do nothing else.
/// * **No existing workout** — start one and navigate to `/workout/active`.
/// * **Existing workout + Resume** — navigate to `/workout/active`, leave
///   the workout intact.
/// * **Existing workout + Discard** — delete the existing workout, start a
///   fresh one, and navigate to `/workout/active`. (B1 regression: the
///   "intend to start fresh" intent must not be silently swallowed.)
/// * **Dialog dismissed** (`result == null`) — unreachable today
///   (`barrierDismissible: false`) but guarded as a no-op for forward
///   compatibility.
Future<void> _startQuickWorkout(BuildContext context, WidgetRef ref) async {
  final isOnline = ref.read(isOnlineProvider);
  if (!isOnline) {
    if (context.mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.offlineStartWorkout)));
    }
    return;
  }

  final existingWorkout = ref.read(activeWorkoutProvider).value;
  if (existingWorkout != null) {
    if (!context.mounted) return;
    final result = await ResumeWorkoutDialog.show(
      context,
      workoutName: existingWorkout.workout.name,
      startedAt: existingWorkout.workout.startedAt,
    );
    if (!context.mounted) return;
    if (result == ResumeWorkoutResult.resume) {
      context.go('/workout/active');
      return;
    }
    if (result == ResumeWorkoutResult.discard) {
      try {
        await ref.read(activeWorkoutProvider.notifier).discardWorkout();
      } catch (_) {
        return; // discard failed — do not silently start a new workout
      }
      if (!context.mounted) return;
      await ref.read(activeWorkoutProvider.notifier).startWorkout();
      if (!context.mounted) return;
      context.go('/workout/active');
      return;
    }
    return; // dialog dismissed — unreachable today, guard for the future
  }
  await ref.read(activeWorkoutProvider.notifier).startWorkout();
  if (!context.mounted) return;
  context.go('/workout/active');
}

// ---------------------------------------------------------------------------
// Branch 1: bucket has an uncompleted entry → "Iniciar {routineName}"
// ---------------------------------------------------------------------------

/// Shown when [suggestedNextProvider] returns a bucket entry. Headline
/// reuses the `homeActionHeroStartRoutine` template ("Iniciar {routineName}"
/// in pt). The subline reuses the existing `exerciseCountDuration` template
/// for parity with the rest of the surfaces that show routine metadata.
class _StartNextRoutineHero extends ConsumerWidget {
  const _StartNextRoutineHero({required this.bucketEntry});

  final BucketRoutine bucketEntry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Guaranteed-present after the `homeReadyProvider` gate in production;
    // `?? const []` survives for direct-widget test rendering.
    final routines = ref.watch(routineListProvider).value ?? const <Routine>[];
    final routine = routines.cast<Routine?>().firstWhere(
      (r) => r?.id == bucketEntry.routineId,
      orElse: () => null,
    );
    // Bucket entry points at a routine that's been deleted out from under
    // us. Render the free-workout fallback identifier so the outer
    // home-action-hero wrapper still has a deterministic inner child. The
    // user can still kick off a quick workout while the data layer
    // reconciles.
    if (routine == null) return const _FreeWorkoutHero(weekComplete: false);

    final l10n = AppLocalizations.of(context);
    final durationMin = estimateRoutineDurationMinutes(routine);
    final subline = l10n.exerciseCountDuration(
      routine.exercises.length,
      durationMin,
    );

    return _HeroBanner(
      // Inlined uppercase Portuguese — single-locale launch (Phase 26f
      // decision). T1's l10n key set did not include eyebrow labels, and we
      // explicitly defer adding them until the second locale lands.
      label: 'INICIAR',
      headline: l10n.homeActionHeroStartRoutine(routine.name),
      subline: subline,
      onTap: () => startRoutineWorkout(context, ref, routine),
      semanticsIdentifier: 'home-action-hero-start-routine',
    );
  }
}

// ---------------------------------------------------------------------------
// Branch 2: bucket empty / fully complete → "Treino livre"
// ---------------------------------------------------------------------------

/// Shown when the user has routines but no uncompleted bucket entry. Covers
/// two underlying states:
///
/// * **Week complete** (`weekComplete == true`) — every planned routine has
///   been finished. Subline reads "Semana completa" as positive
///   reinforcement.
/// * **No plan / bucket empty otherwise** (`weekComplete == false`) — user
///   has not created a plan this week (legacy "lapsed" state) or the plan
///   has zero entries. Subline is omitted so the layout slot stays stable
///   without redundant copy.
///
/// Tapping the card delegates to the shared [_startQuickWorkout] helper,
/// which inherits the resume-vs-start dialog flow from the legacy
/// ActionHero — including the B1 regression fix for "Discard → start fresh".
class _FreeWorkoutHero extends ConsumerWidget {
  const _FreeWorkoutHero({required this.weekComplete});

  final bool weekComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return _HeroBanner(
      label: 'TREINO LIVRE',
      headline: l10n.homeActionHeroFreeWorkout,
      subline: weekComplete
          ? l10n.homeActionHeroFreeWorkoutSubtitleWeekComplete
          : null,
      onTap: () => _startQuickWorkout(context, ref),
      semanticsIdentifier: 'home-action-hero-free-workout',
    );
  }
}

// ---------------------------------------------------------------------------
// Branch 3: routines list is empty → "Criar primeira rotina"
// ---------------------------------------------------------------------------

/// Shown when the user has zero routines. Replaces the legacy
/// `_BrandNewHero` / `_BeginnerCta` flow that surfaced a recommended
/// default routine. The new onboarding direction is to walk the user
/// through creating their own routine.
///
/// Tap pushes `/routines/create`.
class _CreateFirstRoutineHero extends StatelessWidget {
  const _CreateFirstRoutineHero();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _HeroBanner(
      label: 'BEM-VINDO',
      headline: l10n.homeActionHeroCreateFirstRoutine,
      // No new ARB key for the subline. Reuse `pickRoutinesForWeek`'s
      // existing nav-cue copy — semantically close enough for the
      // single-locale launch, and avoids adding a key that T1 didn't budget
      // for.
      subline: l10n.pickRoutinesForWeek,
      onTap: () => context.push('/routines/create'),
      semanticsIdentifier: 'home-action-hero-create-first-routine',
    );
  }
}

// ---------------------------------------------------------------------------
// Shared 80dp banner surface — one Material+InkWell card with a left accent
// border in primary green, label / headline / subline rows, and a trailing
// play glyph. Background flows through theme.cardTheme.color so the banner
// inherits app-wide surface tokens.
// ---------------------------------------------------------------------------

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.label,
    required this.headline,
    this.subline,
    required this.onTap,
    this.semanticsIdentifier,
  });

  /// Small uppercase eyebrow label, e.g. "INICIAR", "TREINO LIVRE",
  /// "BEM-VINDO".
  final String label;

  /// Primary content line — routine name template ("Iniciar Push Day"),
  /// "Treino livre", "Criar primeira rotina".
  final String headline;

  /// Optional metadata line below the headline. When null the banner
  /// renders only the label + headline; the slot collapses.
  final String? subline;

  /// Per-branch Semantics identifier for locale-independent E2E selectors.
  final String? semanticsIdentifier;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: semanticsIdentifier,
      child: Material(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(kRadiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadiusMd),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 80),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kRadiusMd),
                border: Border(
                  left: BorderSide(color: theme.colorScheme.primary, width: 4),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Bare container prevents AOM merging label into
                          // the headline's accessible text node.
                          Semantics(
                            container: true,
                            child: Text(
                              label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: mutedColor,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Semantics(
                            container: true,
                            child: Text(
                              headline,
                              // L15: ActionHero headline — Rajdhani 600 (the
                              // primary home CTA carries display weight per
                              // project_design_language_typography).
                              style: AppTextStyles.headline.copyWith(
                                fontSize: 20,
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          if (subline != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subline!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: mutedColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.play_arrow,
                      color: theme.colorScheme.primary,
                      size: 28,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
