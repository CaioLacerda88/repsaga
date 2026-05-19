import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/radii.dart';
import '../../../l10n/app_localizations.dart';
import '../../routines/models/routine.dart';
import '../../routines/providers/notifiers/routine_list_notifier.dart';
import '../../routines/ui/start_routine_action.dart';
import '../../routines/ui/widgets/routine_action_sheet.dart';
import '../../routines/ui/widgets/routine_card.dart';
import '../../weekly_plan/providers/weekly_plan_provider.dart';
import '../../../shared/widgets/pending_sync_badge.dart';
import '../../../shared/widgets/sync_failure_card.dart';
import 'widgets/action_hero.dart';
import 'widgets/bucket_chip_row.dart';
import 'widgets/character_card.dart';
import 'widgets/encouragement_nudge.dart';
import 'widgets/home_greeting.dart';
import 'widgets/last_session_line.dart';

/// The RepSaga home surface.
///
/// **Phase 26f composition (+ Phase 27 L2 greeting).** Replaces the W8
/// status-line + 7-day-bucket layout with a single-card character surface
/// + chip row, prefixed by a top-of-home greeting:
///
/// 1. Sync chrome             — `PendingSyncBadge` + `SyncFailureCard` for
///                              offline / failed-write affordances.
/// 2. [_ConfirmBanner]        — "Same plan this week?" banner (shown when
///                              `weeklyPlanNeedsConfirmationProvider` is true).
/// 3. [HomeGreeting]          — date eyebrow + display name (Phase 27 L2).
/// 4. [CharacterCard]         — tappable expanding character card. Collapsed
///                              shows level/class/title meta + closest-rank-up
///                              indicator; expanded reveals the full Saga
///                              character sheet (XP bar + 6 body-part rows).
/// 5. [EncouragementNudge]    — one-line rotating-priority hint (cross-build
///                              title close, body-part title close, remaining
///                              workouts, streak, or day-0 fallback).
/// 6. [ActionHero]            — primary CTA. Phase 26f collapsed it into
///                              3 branches: create-first-routine / start-next-
///                              routine-in-bucket / free-workout (with
///                              week-complete subline when applicable).
/// 7. [BucketChipRow]         — week-at-a-glance chip wrap. Hides chips when
///                              the bucket is empty but always surfaces the
///                              "Editar plano →" link.
/// 8. [LastSessionLine]       — editorial "Last: ..." line (hidden when no
///                              history).
/// 9. [_HomeRoutinesList]     — user's routines, top 3 + "See all", only when
///                              no active plan. When the user has no custom
///                              routines yet, falls back to a preview of up
///                              to 3 seeded default routines via
///                              [_DefaultRoutinesPreview] (Phase 27 L3) —
///                              ActionHero owns the "create a routine"
///                              primary CTA on that surface.
///
/// Each block is its own ConsumerWidget — this build method intentionally
/// watches NO providers, so a change in (for example)
/// `workoutHistoryProvider` does not rebuild the character card or chip row.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PendingSyncBadge(),
            SyncFailureCard(),
            _ConfirmBanner(),
            HomeGreeting(),
            CharacterCard(),
            SizedBox(height: 12),
            EncouragementNudge(),
            SizedBox(height: 12),
            ActionHero(),
            SizedBox(height: 16),
            BucketChipRow(),
            SizedBox(height: 16),
            LastSessionLine(),
            SizedBox(height: 16),
            _HomeRoutinesList(),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confirmation banner ("Same plan this week?")
// ---------------------------------------------------------------------------

class _ConfirmBanner extends ConsumerWidget {
  const _ConfirmBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsConfirmation = ref.watch(weeklyPlanNeedsConfirmationProvider);
    if (!needsConfirmation) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(kRadiusMd);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context).samePlanThisWeek,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/plan/week'),
                child: Text(AppLocalizations.of(context).edit),
              ),
              TextButton(
                onPressed: () {
                  ref.read(weeklyPlanNeedsConfirmationProvider.notifier).state =
                      false;
                },
                child: Text(AppLocalizations.of(context).confirm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// My Routines list (only when no active plan)
// ---------------------------------------------------------------------------

/// Maximum number of user routines shown inline on Home. When the user has
/// more, a "See all" pill links to `/routines`.
const _homeRoutineLimit = 3;

class _HomeRoutinesList extends ConsumerWidget {
  const _HomeRoutinesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Scoped subscription: only flips on plan create/clear/empty transitions,
    // so routine-level plan mutations (mark-complete, add, remove) do not
    // force this list to rebuild.
    final hasActivePlan = ref.watch(hasActivePlanProvider);
    if (hasActivePlan) return const SizedBox.shrink();

    final routinesAsync = ref.watch(routineListProvider);
    return routinesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (routines) {
        final userRoutines = routines
            .where((r) => r.userId != null && !r.isDefault)
            .toList();
        if (userRoutines.isEmpty) {
          // Phase 27 L3: the empty-state CTA on this surface used to
          // duplicate ActionHero's day-0 "Criar primeira rotina" call. UX-
          // critic Option B+ (locked 2026-05-18) moved that responsibility
          // back to ActionHero alone and replaced this slot with a preview
          // of the seeded default routines, so day-0 users can start
          // lifting without first walking through the routine-builder.
          return const _DefaultRoutinesPreview();
        }

        final shown = userRoutines.take(_homeRoutineLimit).toList();
        final hasMore = userRoutines.length > _homeRoutineLimit;
        final theme = Theme.of(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).myRoutines,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 8),
            for (final r in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RoutineCard(
                  routine: r,
                  onTap: () => startRoutineWorkout(context, ref, r),
                  onLongPress: () => showRoutineActionSheet(context, ref, r),
                ),
              ),
            if (hasMore)
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  container: true,
                  identifier: 'home-see-all-routines',
                  child: TextButton(
                    onPressed: () => context.go('/routines'),
                    child: Text(AppLocalizations.of(context).seeAll),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Day-0 "starter kit" preview shown when the user has no custom routines.
///
/// Renders up to 3 seeded default routines as tappable cards using the same
/// [RoutineCard] widget the populated MY ROUTINES list uses — so the visual
/// language is consistent across both states and the empty→populated
/// transition needs no animation work (the state IS the transition).
///
/// **Behavior** — tapping a card calls [startRoutineWorkout] for that
/// default routine. It does NOT auto-create a user-owned copy; the user
/// can keep using the seeded routine until they choose to customize via
/// the routine library. ActionHero's `_CreateFirstRoutineHero` branch
/// still owns the "build your own" primary CTA on day-0 (see
/// [ActionHero] class doc for the L3 gate tightening).
///
/// **Anti-patterns (UX-critic Option B+, locked 2026-05-18)** — no
/// uppercase header, no divider, no leading icon, no "See all" chevron
/// (the bottom-nav routines tab covers discovery), no animation, and no
/// curation/filter on which 3 defaults appear (first 3 in the list).
///
/// **Empty defaults edge case** — if the seed RPC hasn't run yet (or
/// returned zero defaults), renders [SizedBox.shrink] so ActionHero owns
/// the day-0 message alone. Graceful no-op, never broken layout.
class _DefaultRoutinesPreview extends ConsumerWidget {
  const _DefaultRoutinesPreview();

  /// Cap on how many seeded defaults render. Mirrors [_homeRoutineLimit]
  /// for the populated MY ROUTINES list — keeps both states at the same
  /// visual weight on Home.
  static const int _previewLimit = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routineListProvider).value ?? const <Routine>[];
    final defaults = routines.where((r) => r.isDefault).toList();
    if (defaults.isEmpty) return const SizedBox.shrink();

    final shown = defaults.take(_previewLimit).toList();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).homeStarterRoutinesLabel,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 8),
        for (final r in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RoutineCard(
              routine: r,
              // Same tap path as the populated MY ROUTINES card — the
              // seeded routine starts a real workout, identical to a
              // user-owned routine. Reuses [startRoutineWorkout]'s
              // offline / resume-vs-start guards.
              onTap: () => startRoutineWorkout(context, ref, r),
            ),
          ),
      ],
    );
  }
}
