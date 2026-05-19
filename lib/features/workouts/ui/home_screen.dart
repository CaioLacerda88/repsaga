import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/radii.dart';
import '../../../l10n/app_localizations.dart';
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
///                              no active plan.
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
          return const _CreateRoutineCta();
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

class _CreateRoutineCta extends StatelessWidget {
  const _CreateRoutineCta();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(kRadiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusMd),
        onTap: () => context.go('/routines/create'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  Icons.add_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context).createYourFirstRoutine,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
