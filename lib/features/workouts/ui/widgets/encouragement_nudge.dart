import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../rpg/domain/titles_view_model.dart';
import '../../../rpg/models/body_part.dart';
import '../../../rpg/models/title.dart' as rpg;
import '../../../rpg/providers/character_sheet_provider.dart';
import '../../../rpg/providers/earned_titles_provider.dart';
import '../../../rpg/providers/rpg_progress_provider.dart';
import '../../../rpg/ui/widgets/body_part_localization.dart';
import '../../../rpg/ui/widgets/title_localization.dart';
import '../../../weekly_plan/providers/suggested_next_provider.dart';
import '../../domain/encouragement_nudge_priority.dart';
import '../../providers/streak_provider.dart';

/// Single ~24dp line above the home ActionHero (Phase 26f).
///
/// Surfaces one of five rotating-priority hints resolved by
/// [selectNudge]:
///
///   1. Cross-build title within 1 rank of every condition
///   2. Body-part title within 1 rank of next threshold
///   3. Remaining bucket workouts for the current week
///   4. Current consecutive-day streak
///   5. First-step fallback (day-0 user)
///
/// **Why the resolver is called here, not in a provider.** The five inputs
/// are already individually reactive (streak, completed/total counts, the
/// three titles-view sources). Wrapping the resolver in a separate provider
/// would force a redundant rebuild step and complicate test overrides.
/// `selectNudge` is a pure function — the widget calls it directly with
/// the watched values.
///
/// **Why no `titlesViewProvider`.** [TitlesViewModel.split] is a static
/// splitter, not a Riverpod-exposed provider — the titles screen also
/// composes it inline from [titleCatalogProvider], [earnedTitlesProvider],
/// and [rpgProgressProvider]. T5 doesn't add a new provider for it
/// because the orchestrator hasn't authorized that surface; T11 may
/// extract a memoized view-state provider if the home screen + titles
/// screen start sharing the computation.
///
/// **Within 1 rank filter.** Body-part nudges fire when a row in
/// `TitlesView.nextRows` has `thresholdValue - currentValue == 1`. The
/// view-model's cross-build filter ALREADY enforces "every condition
/// within 1 rank" — so we surface the first `crossBuildCards` entry
/// without re-filtering.
///
/// **Loading semantics.** While the catalog or earned-titles futures are
/// still resolving, the widget falls back to the first-step copy rather
/// than rendering nothing. Two reasons: (1) preserves the 24dp height so
/// ActionHero doesn't pop down on hydrate, and (2) the fallback copy is
/// also the correct steady-state for a brand-new user, so the worst-case
/// transition is fallback → fallback (no visible change).
///
/// **L10n strategy.** This widget is single-use (only on the Home screen
/// above ActionHero) so it reads [AppLocalizations.of] directly. Per
/// `feedback_widget_l10n_parameterization`, reusable widgets should take
/// localized strings as constructor params; one-shot screen-bound widgets
/// can read l10n inline.
class EncouragementNudge extends ConsumerWidget {
  const EncouragementNudge({super.key});

  /// Fixed ~24dp line height. Exposed as a constant so [ActionHero] /
  /// home layout can reserve the same vertical slot when the widget is
  /// briefly hidden during hot-reload or auth churn.
  static const double height = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    // Day-0 suppression. CharacterCard's `_ClosestRankUpRow` fallback
    // already carries the day-0 first-step copy
    // (`homeFirstStepFallback`). Rendering the same string here would
    // duplicate it on the home surface for a brand-new user, so we
    // collapse the nudge to a layout-preserving empty slot. The Semantics
    // identifier stays attached so E2E specs that hook on
    // `home-encouragement-nudge` keep resolving. L2 fix (visual
    // verification, 2026-05-18).
    final sheet = ref.watch(characterSheetProvider).value;
    if (sheet != null && sheet.isZeroHistory) {
      // `Semantics` has no const constructor — wrap the const SizedBox
      // inline. Height matches [EncouragementNudge.height] so the slot
      // stays the same vertical size whether the nudge is suppressed or
      // surfaced.
      return Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: 'home-encouragement-nudge',
        child: const SizedBox(height: height),
      );
    }

    // Reactive inputs — five providers, one resolver call. Each watch
    // updates the line on the next frame when the underlying value
    // changes; the resolver is pure so re-running it is free.
    final streakDays = ref.watch(streakProvider);
    final completed = ref.watch(completedCountProvider);
    final total = ref.watch(totalBucketCountProvider);
    final catalogAsync = ref.watch(titleCatalogProvider);
    final earnedAsync = ref.watch(earnedTitlesProvider);
    final progressAsync = ref.watch(rpgProgressProvider);

    // Bucket "remaining" — clamp at 0 in case the server lands a stale
    // total before the completed-count refresh propagates.
    final remaining = (total - completed).clamp(0, 1 << 30);

    // Resolve the titles view from the three upstream providers. Mirrors
    // the titles_screen.dart composition. If catalog or earned are still
    // loading, we leave the title slots null — the resolver falls
    // through to remaining / streak / first-step.
    String? crossBuildClose;
    ({BodyPart bodyPart, String titleName})? bodyPartTitleClose;

    final catalog = catalogAsync.value;
    final earned = earnedAsync.value;
    if (catalog != null && earned != null) {
      final snapshot = progressAsync.value ?? RpgProgressSnapshot.empty;
      final ranks = <BodyPart, int>{
        for (final bp in activeBodyParts)
          bp: snapshot.byBodyPart[bp]?.rank ?? 1,
      };
      final view = TitlesViewModel.split(
        catalog: catalog,
        earned: earned,
        ranks: ranks,
        characterLevel: snapshot.characterState.characterLevel,
      );

      // Cross-build: view-model already filters "every condition within 1
      // rank". Surfacing the first entry is sufficient — there are at
      // most 5 cross-build titles in v1 and the user can only be near
      // one or two at a time.
      if (view.crossBuildCards.isNotEmpty) {
        final card = view.crossBuildCards.first;
        crossBuildClose = localizedTitleCopy(card.title.slug, l10n)?.name;
      }

      // Body-part title within 1 rank — `nextRows` already excludes
      // already-earned and maxed-out tracks. We pick the FIRST row whose
      // `thresholdValue - currentValue == 1`, ignoring character-level
      // rows (their `currentValue` is a character level, not a rank, so
      // the "1 away" semantics differ — the spec intentionally limits
      // this nudge slot to body-part tracks).
      if (crossBuildClose == null) {
        for (final row in view.nextRows) {
          final title = row.title;
          if (title is! rpg.BodyPartTitle) continue;
          if (row.thresholdValue - row.currentValue != 1) continue;
          final name = localizedTitleCopy(title.slug, l10n)?.name;
          if (name == null) continue;
          bodyPartTitleClose = (bodyPart: title.bodyPart, titleName: name);
          break;
        }
      }
    }

    final nudge = selectNudge(
      crossBuildClose: crossBuildClose,
      bodyPartTitleClose: bodyPartTitleClose,
      remainingBucketWorkouts: remaining,
      streakDays: streakDays,
    );

    final text = switch (nudge) {
      NudgeCrossBuildClose(:final titleName) => l10n.homeNudgeCrossBuildClose(
        titleName,
      ),
      NudgeBodyPartTitleClose(:final bodyPart, :final titleName) =>
        l10n.homeNudgeBodyPartTitleClose(
          localizedBodyPartName(bodyPart, l10n),
          titleName,
        ),
      NudgeRemainingWorkouts(:final count) => l10n.homeNudgeRemainingWorkouts(
        count,
      ),
      NudgeStreak(:final days) => l10n.homeNudgeStreakDays(days),
      NudgeFirstStep() => l10n.homeFirstStepFallback,
    };

    return Semantics(
      // `container: true` + `explicitChildNodes: true` keeps the
      // identifier reachable on Flutter web's AOM — see
      // `cluster_semantics_identifier_pair_rule`. Future E2E selectors
      // can hook on `home-encouragement-nudge` without having to grep
      // localized text.
      container: true,
      explicitChildNodes: true,
      identifier: 'home-encouragement-nudge',
      child: SizedBox(
        height: height,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            text,
            style: AppTextStyles.body.copyWith(
              fontSize: 13,
              color: AppColors.textDim,
              letterSpacing: 0.02 * 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
