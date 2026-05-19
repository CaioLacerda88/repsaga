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

    // Resolve the full rendered line + the substring(s) that should render
    // in the bold-cream emphasis style. `_NudgeFragments.full` is the
    // ARB-rendered string; `boldFragments` is an ordered list of substrings
    // to wrap in `FontWeight.w700` + `AppColors.textCream` via Text.rich
    // (the rest stays muted `textDim`). The list is ordered by first
    // occurrence so the slicing helper consumes them left-to-right.
    //
    // L11.a (Phase 27, 2026-05-19) — mockup `.nudge strong` calls for
    // count+noun / title-name emphasis on every numeric variant. We slice
    // the rendered string at the placeholder substring instead of adding
    // sibling ARB keys ("BoldFragment" suffix variants); the placeholder
    // values themselves (`"3 workouts"`, `"Iron-Bound"`, etc.) are already
    // present verbatim inside the full line, so a `String.indexOf` split
    // works for both locales without ARB churn. Defensive: if the fragment
    // isn't found (e.g. a future locale phrases the noun differently),
    // the helper falls back to rendering the whole line muted-but-plain.
    final fragments = switch (nudge) {
      NudgeCrossBuildClose(:final titleName) => _NudgeFragments(
        full: l10n.homeNudgeCrossBuildClose(titleName),
        boldFragments: [titleName],
      ),
      NudgeBodyPartTitleClose(:final bodyPart, :final titleName) => () {
        final bodyPartName = localizedBodyPartName(bodyPart, l10n);
        return _NudgeFragments(
          full: l10n.homeNudgeBodyPartTitleClose(bodyPartName, titleName),
          boldFragments: [bodyPartName, titleName],
        );
      }(),
      NudgeRemainingWorkouts(:final count) => _NudgeFragments(
        full: l10n.homeNudgeRemainingWorkouts(count),
        // Bold fragment varies by locale — derive it by formatting a
        // throw-away version of the same plural template with a known
        // sentinel and slicing the recurring noun off the full line.
        // Cheaper: pull the noun directly via a second ARB call would
        // require new keys; instead we use the precomputed plural fragments
        // assembled below.
        boldFragments: [_remainingWorkoutsBoldFragment(l10n, count)],
      ),
      NudgeStreak(:final days) => _NudgeFragments(
        full: l10n.homeNudgeStreakDays(days),
        boldFragments: [_streakBoldFragment(l10n, days)],
      ),
      NudgeFirstStep() => _NudgeFragments(
        full: l10n.homeFirstStepFallback,
        // First-step has no fragment to emphasize — stays fully muted.
        // No leading diamond either.
        boldFragments: const <String>[],
        showLeadingDiamond: false,
      ),
    };

    // Mockup spec (`docs/phase-26-mockups.html` `.nudge`):
    //   `font-family: 'Rajdhani'; font-weight: 500; font-size: 11px;
    //    color: var(--text-dim); letter-spacing: 0.04em; line-height: 1.4;`
    //   `.nudge strong { color: var(--success); font-weight: 700; }`
    // Base text is Rajdhani 500 textDim; the bold span flips to SUCCESS GREEN
    // (not textCream — that was a misread of the L11 spec) at weight 700.
    final baseStyle = const TextStyle(
      fontFamily: 'Rajdhani',
      fontWeight: FontWeight.w500,
      fontSize: 11,
      color: AppColors.textDim,
      letterSpacing: 0.04 * 11,
      height: 1.4,
    );
    final boldStyle = baseStyle.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.success,
    );
    final diamondStyle = baseStyle.copyWith(color: AppColors.hotViolet);

    return Semantics(
      // `container: true` + `explicitChildNodes: true` keeps the
      // identifier reachable on Flutter web's AOM — see
      // `cluster_semantics_identifier_pair_rule`. Future E2E selectors
      // can hook on `home-encouragement-nudge` without having to grep
      // localized text. Text.rich preserves the merged AOM label
      // (`cluster_aom_label_text_merge` is a non-issue here — Text.rich
      // exposes the joined string to assistive tech).
      container: true,
      explicitChildNodes: true,
      identifier: 'home-encouragement-nudge',
      child: SizedBox(
        height: height,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text.rich(
            TextSpan(
              children: [
                if (fragments.showLeadingDiamond)
                  TextSpan(text: '◆ ', style: diamondStyle),
                ..._splitBoldSpans(
                  fragments.full,
                  fragments.boldFragments,
                  baseStyle,
                  boldStyle,
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Resolved rendering inputs for a single nudge variant.
///
/// [full] is the fully-rendered l10n string (after placeholder
/// interpolation). [boldFragments] are substrings inside [full] that should
/// render in the bold-cream emphasis style; the rest of [full] stays muted.
/// [showLeadingDiamond] gates the `◆ ` prefix — only the numeric variants
/// surface it; first-step stays bare.
class _NudgeFragments {
  const _NudgeFragments({
    required this.full,
    required this.boldFragments,
    this.showLeadingDiamond = true,
  });

  final String full;
  final List<String> boldFragments;
  final bool showLeadingDiamond;
}

/// Slices [full] into a sequence of [TextSpan]s, wrapping each fragment in
/// [boldFragments] (in order of appearance) with [boldStyle] and the rest
/// with [baseStyle]. Fragments are matched left-to-right via
/// [String.indexOf] starting at the previous fragment's end — overlapping
/// fragments are not supported but the two callers (single-fragment and
/// body-part-then-title) pass disjoint substrings.
///
/// Defensive fallback: if any fragment cannot be located in [full] (e.g.
/// a future locale phrases the noun differently), the helper short-circuits
/// to a single [baseStyle] span containing the whole line — better to render
/// muted-plain than to crash or silently drop content.
List<TextSpan> _splitBoldSpans(
  String full,
  List<String> boldFragments,
  TextStyle baseStyle,
  TextStyle boldStyle,
) {
  if (boldFragments.isEmpty) {
    return [TextSpan(text: full, style: baseStyle)];
  }
  final out = <TextSpan>[];
  var cursor = 0;
  for (final fragment in boldFragments) {
    if (fragment.isEmpty) continue;
    final idx = full.indexOf(fragment, cursor);
    if (idx < 0) {
      // Fragment missing — bail to the safe fallback (whole line muted).
      return [TextSpan(text: full, style: baseStyle)];
    }
    if (idx > cursor) {
      out.add(TextSpan(text: full.substring(cursor, idx), style: baseStyle));
    }
    out.add(TextSpan(text: fragment, style: boldStyle));
    cursor = idx + fragment.length;
  }
  if (cursor < full.length) {
    out.add(TextSpan(text: full.substring(cursor), style: baseStyle));
  }
  return out;
}

/// Bold-fragment derivation for [NudgeRemainingWorkouts]. The full ARB
/// string interpolates the count into a localized noun phrase ("3 workouts" /
/// "3 treinos"); we re-derive the noun-phrase substring by stripping the
/// surrounding wrapper from the rendered full line.
///
/// Strategy: format the same plural with a sentinel count, locate the
/// sentinel-bearing substring, then re-apply the same template to the
/// actual count. Cheaper alternative considered (new ARB key) deemed not
/// worth the locale churn — this helper is a 6-line search.
///
/// For en + pt v1, the bold fragment matches:
///   en singular: "1 workout"
///   en plural:   "{N} workouts"
///   pt singular: "1 treino"
///   pt plural:   "{N} treinos"
///
/// Both locales place the noun phrase contiguously, so a substring search
/// against the rendered full line + the count digits + the noun word works
/// without per-locale branching. We bound the search by locating the
/// substring that starts with the count's string form.
String _remainingWorkoutsBoldFragment(AppLocalizations l10n, int count) {
  // Build the full line, then pull the contiguous noun phrase out by
  // anchoring on the count's textual form. The "1" branch is anchored
  // verbatim (no localization-driven number formatting splits a leading
  // "1"); the plural branch falls back to the count's string.
  final full = l10n.homeNudgeRemainingWorkouts(count);
  // Find the count digits in `full` and walk forward to the next sentence
  // terminator that isn't a digit/letter (the bold fragment ends at the
  // first space-led particle: " para" / " to ").
  final countStr = '$count';
  final start = full.indexOf(countStr);
  if (start < 0) return full; // defensive — let the splitter fall back
  // Walk forward from `start` until we hit the locale-specific tail
  // particle. For en that's " to close"; for pt that's " para fechar".
  // Both contain " to " / " para " — match the first occurrence of either.
  final tailEn = full.indexOf(' to ', start);
  final tailPt = full.indexOf(' para ', start);
  final tail = (tailEn >= 0 && (tailPt < 0 || tailEn < tailPt))
      ? tailEn
      : tailPt;
  if (tail < 0) return full.substring(start); // very defensive
  return full.substring(start, tail);
}

/// Bold-fragment derivation for [NudgeStreak]. The plural rendering is
/// itself the bold fragment ("1-day streak" / "3-day streak" / "3 dias de
/// sequência") — no surrounding sentence to strip. Returning the full line
/// makes the whole nudge bold + cream, matching the mockup's `.nudge strong`
/// which wraps the entire streak phrase.
String _streakBoldFragment(AppLocalizations l10n, int days) {
  return l10n.homeNudgeStreakDays(days);
}
