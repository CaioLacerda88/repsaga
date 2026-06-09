import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/providers/profile_providers.dart';
import '../../routines/models/routine.dart';
import '../../routines/providers/notifiers/routine_list_notifier.dart';
import '../../routines/providers/routine_hint_provider.dart';
import '../../routines/ui/start_routine_action.dart';
import '../../routines/ui/widgets/routine_action_sheet.dart';
import '../../routines/ui/widgets/routine_card.dart';
import '../../routines/ui/widgets/routine_long_press_hint.dart';
import '../../weekly_plan/providers/weekly_plan_provider.dart';
import '../../../shared/widgets/pending_sync_badge.dart';
import '../../../shared/widgets/sync_failure_card.dart';
import '../providers/workout_history_providers.dart';
import 'widgets/action_hero.dart';
import 'widgets/bucket_chip_row.dart';
import 'widgets/character_card.dart';
import 'widgets/encouragement_nudge.dart';
import 'widgets/home_greeting.dart';
import 'widgets/last_session_line.dart';

/// Resolves when the four CRITICAL-PATH providers for Home's first paint
/// have all emitted data — `workoutCount`, `routineList`, `profile`, and
/// `weeklyPlan`. While this future is pending, [HomeScreen] renders
/// [_HomeSkeleton]; on resolution it renders the real tree.
///
/// Why exactly these four and no others:
///   * `workoutCountProvider` gates the [ActionHero] branch decision
///     between "create first routine" and "start next routine / free
///     workout". Loading it as `.value ?? 0` (the prior approach)
///     falsely satisfied the day-0 gate for returning users, who saw a
///     "Criar primeira rotina" flash before the count resolved.
///   * `routineListProvider` is the L3 tightening of the same gate — a
///     user with workouts but no user-built routines still hits day-0.
///     Loading it as `.value ?? []` had the same false-positive shape.
///   * `profileProvider` feeds the headline-22sp Rajdhani name slot in
///     [HomeGreeting]. The first text element the user reads on Home;
///     an empty or email-prefix-stub name flashing to the display name
///     is high-visibility damage.
///   * `weeklyPlanProvider` is the source [suggestedNextProvider]
///     derives from. Without it [ActionHero] would default to the
///     free-workout branch and snap to "Iniciar X" on plan arrival —
///     worse than holding the skeleton.
///
/// Everything else (`workoutHistory` → streak, `titles`, `rpgProgress` /
/// `characterSheet`) is intentionally BEST-EFFORT: [CharacterCard] owns
/// its own per-widget skeleton, the streak nudge is below the fold,
/// title-derived nudges have a safe first-step fallback. Holding the
/// whole screen on those would inflate cold-mount latency for surfaces
/// that already handle their own loading state correctly.
final homeReadyProvider = FutureProvider<void>((ref) async {
  // `Future.wait` lets the four round-trips run in parallel — total
  // gate latency is `max(t_workoutCount, t_routineList, t_profile,
  // t_weeklyPlan)`, not their sum. `workoutCountProvider` is
  // `keepAlive`, so on subsequent navigations to Home it resolves
  // synchronously (no flicker, no skeleton).
  await Future.wait<dynamic>([
    ref.watch(workoutCountProvider.future),
    ref.watch(routineListProvider.future),
    ref.watch(profileProvider.future),
    ref.watch(weeklyPlanProvider.future),
  ]);
});

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
/// Each block is its own ConsumerWidget. The outer `HomeScreen` watches
/// [homeReadyProvider] only — that future awaits the four critical-path
/// providers so the first paint is gated until ActionHero's branch
/// decision, HomeGreeting's name slot, and BucketChipRow's plan data are
/// all guaranteed-present. While loading, [_HomeSkeleton] holds the
/// layout dimensions; on hydrate the real tree swaps in with identical
/// outer scaffolding so the repaint is a text/icon population, not a
/// layout shift.
///
/// Best-effort providers (`workoutHistory` → streak, `titles` →
/// encouragement nudge variants, `rpgProgress` → character card) are
/// NOT in the gate — they each handle their own loading state in their
/// own widget. Adding them here would inflate every cold-mount with
/// the heaviest provider's latency for surfaces that already do
/// per-widget skeletons correctly (e.g. [CharacterCard]).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(homeReadyProvider);
    // [PendingSyncBadge] + [SyncFailureCard] are rendered OUTSIDE the
    // skeleton gate so they remain mounted regardless of
    // [homeReadyProvider]'s state. Without this lift, going offline
    // would hang the gate (Supabase futures never resolve) and the
    // user would see only the skeleton — losing the very offline /
    // sync-failure affordances they need precisely in that state.
    // Both widgets are internally `SizedBox.shrink` when there's
    // nothing to show, so the unconditional mount has zero visible
    // cost in the steady state.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PendingSyncBadge(),
            const SyncFailureCard(),
            // Gate-dependent content below — skeleton on first cold mount,
            // real tree once the four critical providers resolve, real
            // tree on error too (per the comment on the original gate:
            // holding the skeleton on error would silently hide the
            // screen with no path back).
            ready.when(
              data: (_) => const _HomeBody(),
              error: (_, _) => const _HomeBody(),
              loading: () => const _HomeSkeleton(),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
    );
  }
}

/// Static placeholder frame rendered while [homeReadyProvider] is
/// pending. Per UX-critic direction (locked 2026-05-19):
///   * Surface color is [AppColors.surface] — identical to the real
///     widgets, so the hydrate swap is invisible rather than a tonal
///     flash.
///   * Static, no shimmer, no pulse. Animation reads as "broken app"
///     on a gym floor; a static gray block reads as "loading" within
///     300ms with no distracting motion.
///   * Per-slot dimensions match the real widgets' steady-state
///     dimensions exactly, so the hydrate transitions text/icon onto
///     the same boxes without any layout shift.
///   * [CharacterCard] is NOT in the skeleton's place; the gate has
///     resolved by the time the body renders. CharacterCard's own
///     internal skeleton (the only widget that did this correctly
///     pre-fix) continues to handle its own loading independently.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GreetingSkeleton(),
        _SkeletonBlock(height: 118, radius: kRadiusLg), // CharacterCard
        SizedBox(height: 12),
        _SkeletonBlock(height: 24, radius: kRadiusSm), // EncouragementNudge
        SizedBox(height: 12),
        _SkeletonBlock(height: 80, radius: kRadiusMd), // ActionHero
        SizedBox(height: 16),
        _BucketHeaderSkeleton(),
        SizedBox(height: 16),
        // LastSessionLine and _HomeRoutinesList both render
        // SizedBox.shrink while their best-effort sources load;
        // omitting their skeletons keeps the placeholder height
        // bounded to the visible-on-load area.
        SizedBox(height: 24),
      ],
    );
  }
}

/// Skeleton equivalent for [HomeGreeting]: two stacked block
/// placeholders matching the eyebrow (10dp) + name (22dp) line heights
/// + the 14dp bottom padding the real widget uses. Cannot reuse
/// [HomeGreeting] itself because that widget watches
/// `profileProvider` — pre-resolve it would render an empty/email-
/// prefix name flashing to the display name on hydrate, the very
/// jank this skeleton exists to suppress.
class _GreetingSkeleton extends StatelessWidget {
  const _GreetingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 140,
            child: _SkeletonBlock(height: 10, radius: kRadiusSm),
          ),
          SizedBox(height: 2),
          SizedBox(
            width: 180,
            child: _SkeletonBlock(height: 22, radius: kRadiusSm),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.height, required this.radius});

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Matches the real [BucketChipRow]'s minimum-height shape: the "ESTA
/// SEMANA" header line + the "EDITAR PLANO →" footer link, both real,
/// with the chip wrap area as a single subtle placeholder block. The
/// header and footer survive into the data state, so the user sees
/// the layout's edges immediately — only the chips fade in.
class _BucketHeaderSkeleton extends StatelessWidget {
  const _BucketHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 100,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(kRadiusSm),
              ),
            ),
            const Spacer(),
            Container(
              width: 64,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(kRadiusSm),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const _SkeletonBlock(height: 32, radius: kRadiusSm),
      ],
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
                  style: AppTextStyles.body.copyWith(
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
                  // PR 32g — durable Hive write replaces the in-memory
                  // StateProvider mutation. Fire-and-forget is fine: the
                  // notifier updates `state` synchronously BEFORE the
                  // Hive box write completes, so the banner hides on the
                  // next frame regardless of disk-write latency.
                  ref
                      .read(weeklyPlanNeedsConfirmationProvider.notifier)
                      .set(false);
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
              style: AppTextStyles.label.copyWith(
                fontSize: 13,
                letterSpacing: 0.12 * 13,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 8),
            // One-time long-press discoverability hint, between the MY
            // ROUTINES eyebrow and the first card. Self-gates to nothing once
            // the gesture is discovered or the view cap is reached. The home
            // section already sits inside the page's 16dp horizontal padding,
            // so the hint takes `horizontalPadding: 0` to align its glyph to
            // the same x=16 card edge instead of doubling the inset.
            RoutineLongPressHint(
              label: AppLocalizations.of(context).hintRoutineLongPress,
              horizontalPadding: 0,
            ),
            for (final r in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RoutineCard(
                  routine: r,
                  onTap: () => startRoutineWorkout(context, ref, r),
                  onLongPress: () {
                    ref.read(routineHintProvider.notifier).markSeen();
                    showRoutineActionSheet(context, ref, r);
                  },
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
          style: AppTextStyles.label.copyWith(
            fontSize: 13,
            letterSpacing: 0.12 * 13,
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
