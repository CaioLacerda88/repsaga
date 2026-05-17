import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/titles_view_model.dart';
import '../models/body_part.dart';
import '../models/title.dart' as rpg;
import '../providers/earned_titles_provider.dart';
import '../providers/rpg_progress_provider.dart';
import 'utils/vitality_state_styles.dart';
import 'widgets/body_part_localization.dart';
import 'widgets/cross_build_card.dart';
import 'widgets/earned_title_row.dart';
import 'widgets/equipped_title_card.dart';
import 'widgets/next_title_row.dart';
import 'widgets/title_localization.dart';
import 'widgets/titles_counter_pill.dart';

/// `/saga/titles` — Titles surface (Phase 26d).
///
/// Three regions, top to bottom:
///   * **Equipado** — the single currently-equipped title rendered as an
///     [EquippedTitleCard] (heroGold gradient surface). Absent when no title
///     is equipped.
///   * **Conquistados** — earned-but-not-equipped titles as a list of
///     [EarnedTitleRow] entries, most recent first. Each row carries an
///     "Equipar" CTA.
///   * **Próximos** — locked titles, ordered: cross-build [CrossBuildCard]s
///     first (each rendered when within 1 rank of every condition), then one
///     [NextTitleRow] per body-part track, then the next character-level
///     [NextTitleRow] last (mockup ordering).
///
/// AppBar `actions` slot renders a [TitlesCounterPill] showing
/// `{earned}/{total}` once data is loaded.
///
/// **Architecture decisions:**
///   * **Pure consumer widget.** No notifier of its own. The screen reads
///     [titleCatalogProvider], [earnedTitlesProvider], and
///     [rpgProgressProvider] via Riverpod, hands them to
///     [TitlesViewModel.split] (pure domain function), and renders the
///     resulting [TitlesView]. Equip writes go straight through
///     [TitlesRepository.equipTitle] and invalidate the relevant providers.
///   * **View-model split, not inline grouping.** Phase 18c walked the
///     catalog inline in the body widget. 26d moves that into
///     [TitlesViewModel.split] so the three-region selection contract is
///     unit-testable without a `ProviderContainer` and the screen can swap
///     how it composes the inputs without churning the view-model.
///   * **No flavor preview wired in v1.** The widgets accept `onTap` for a
///     future lore bottom-sheet; v1 passes null so the rows degrade to
///     non-tappable surfaces. The equip CTA on [EarnedTitleRow] stays wired.
///   * **Equip path waits for the round-trip.** Optimistic UI is *not* used
///     — equipping a title is a once-a-week interaction; correctness wins
///     over snappiness. After the RPC returns, we invalidate
///     [earnedTitlesProvider] and [equippedTitleSlugProvider] so the screen
///     reflects the new active row and the character sheet's title pill
///     picks up the change on next visit.
///
/// **Loading + error states:**
///   * The screen treats catalog + earned + rpg-progress as a single unit.
///     While any is loading we render [_TitlesSkeleton]; on any error we
///     render [_ErrorState] with the first error message. The pill is
///     suppressed during loading/error so we don't flash `0 / 0` counts.
class TitlesScreen extends ConsumerStatefulWidget {
  const TitlesScreen({super.key});

  @override
  ConsumerState<TitlesScreen> createState() => _TitlesScreenState();
}

class _TitlesScreenState extends ConsumerState<TitlesScreen> {
  /// Slug of the row whose `equipTitle` round-trip is in flight. Locks the
  /// equip handler so a double-tap doesn't fire two writes; cleared in
  /// `finally`. We keep this in widget state (not a provider) because it's
  /// purely transient UI feedback.
  String? _equippingSlug;

  /// Equip an earned (non-active) title. Async caller pattern:
  /// `cluster_async_caller_broke_snackbar` — we `await` the RPC before
  /// invalidating providers so the read side sees the new `is_active` row
  /// when it rebuilds.
  Future<void> _equip(String slug) async {
    if (_equippingSlug != null) return; // re-entrancy guard.
    setState(() => _equippingSlug = slug);
    try {
      final repo = ref.read(titlesRepositoryProvider);
      await repo.equipTitle(slug);
      ref.invalidate(earnedTitlesProvider);
      ref.invalidate(equippedTitleSlugProvider);
    } finally {
      if (mounted) setState(() => _equippingSlug = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalogAsync = ref.watch(titleCatalogProvider);
    final earnedAsync = ref.watch(earnedTitlesProvider);
    final progressAsync = ref.watch(rpgProgressProvider);

    final showCounter = catalogAsync.hasValue && earnedAsync.hasValue;

    return Semantics(
      // `container: true` forces Flutter to emit a flt-semantics node for
      // this identifier even when no descendant Semantics carries
      // label/role/action. Without it, Flutter web's AOM elides
      // identifier-only wrappers from the accessibility tree on rebuild,
      // breaking E2E selectors.
      container: true,
      identifier: 'titles-screen',
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.titlesScreenTitle),
          actions: [
            if (showCounter)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: TitlesCounterPill(
                    earnedCount: earnedAsync.requireValue.length,
                    totalCount: catalogAsync.requireValue.length,
                  ),
                ),
              ),
          ],
        ),
        body: _buildBody(catalogAsync, earnedAsync, progressAsync, l10n),
      ),
    );
  }

  /// Combine the three async branches into a single loading/error/data
  /// switch. The previous implementation flashed two stacked spinners on
  /// cold open; here we treat them as a unit and only enter the data branch
  /// once all three resolved.
  ///
  /// `rpgProgressProvider` errors are *not* treated as catalog failures —
  /// the screen falls back to a default rank-1 distribution so the
  /// "Próximos" region still renders meaningfully when the rank fetch fails.
  Widget _buildBody(
    AsyncValue<List<rpg.Title>> catalogAsync,
    AsyncValue<List<EarnedTitleEntry>> earnedAsync,
    AsyncValue<RpgProgressSnapshot> progressAsync,
    AppLocalizations l10n,
  ) {
    if (catalogAsync.hasError) {
      return _ErrorState(message: '${catalogAsync.error}');
    }
    if (earnedAsync.hasError) {
      return _ErrorState(message: '${earnedAsync.error}');
    }
    if (catalogAsync.isLoading || earnedAsync.isLoading) {
      return const _TitlesSkeleton();
    }
    // RPG snapshot is allowed to be loading/missing — falls back to a
    // default rank-1 distribution + character level 1. This avoids a third
    // loading branch for what's purely additional stat data.
    final snapshot = progressAsync.value ?? RpgProgressSnapshot.empty;
    final ranks = <BodyPart, int>{
      for (final bp in activeBodyParts) bp: snapshot.byBodyPart[bp]?.rank ?? 1,
    };
    final view = TitlesViewModel.split(
      catalog: catalogAsync.requireValue,
      earned: earnedAsync.requireValue,
      ranks: ranks,
      characterLevel: snapshot.characterState.characterLevel,
    );
    return _ThreeRegions(view: view, onEquip: _equip);
  }
}

/// Renders the three regions (Equipado · Conquistados · Próximos) of the
/// Titles screen as a single [ListView]. Pulled out as a stateless widget
/// so the [_TitlesScreenState] equip handler can pass through without
/// re-creating the widget tree on every state ticker.
class _ThreeRegions extends StatelessWidget {
  const _ThreeRegions({required this.view, required this.onEquip});

  final TitlesView view;

  /// Equip callback for [EarnedTitleRow]s. Receives the slug of the row
  /// whose "Equipar" CTA was tapped.
  final Future<void> Function(String slug) onEquip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final children = <Widget>[];

    // ─── Region 1: Equipado ──────────────────────────────────────────────
    if (view.equipped != null) {
      final entry = view.equipped!;
      final title = entry.title;
      children
        ..add(
          _RegionHeader(
            label: l10n.titlesRegionEquipped,
            identifier: 'titles-region-equipped',
          ),
        )
        ..add(const SizedBox(height: 8))
        ..add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: EquippedTitleCard(
              titleName: _titleName(title, l10n),
              bodyPartLabel: _scopeLabel(title, l10n),
              thresholdLabel: _thresholdLabel(title, l10n),
              accentColor: _accentColor(title),
            ),
          ),
        )
        ..add(const SizedBox(height: 24));
    }

    // ─── Region 2: Conquistados ──────────────────────────────────────────
    if (view.earned.isNotEmpty) {
      children
        ..add(
          _RegionHeader(
            label: l10n.titlesRegionEarned,
            identifier: 'titles-region-earned',
          ),
        )
        ..add(const SizedBox(height: 8));
      for (final entry in view.earned) {
        final title = entry.title;
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: EarnedTitleRow(
              slug: title.slug,
              titleName: _titleName(title, l10n),
              bodyPartLabel: _scopeLabel(title, l10n),
              thresholdLabel: _thresholdLabel(title, l10n),
              accentColor: _accentColor(title),
              onEquip: () => onEquip(title.slug),
            ),
          ),
        );
      }
      children.add(const SizedBox(height: 24));
    }

    // ─── Region 3: Próximos ──────────────────────────────────────────────
    // Always present — even an empty next list still shows the header so
    // the user knows what section they're on. The view-model can skip
    // body-part tracks that are maxed out, so the next-rows list might be
    // shorter than 6.
    children
      ..add(
        _RegionHeader(
          label: l10n.titlesRegionNext,
          identifier: 'titles-region-next',
        ),
      )
      ..add(const SizedBox(height: 8));

    // 3a — Cross-build cards first. They surface a denser, multi-condition
    // narrative ("Iron-Bound: chest 59/60, back 60/60, legs 60/60") and
    // belong at the top of "Próximos" where the eye lands first.
    for (final card in view.crossBuildCards) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CrossBuildCard(
            slug: card.title.slug,
            titleName: _titleName(card.title, l10n),
            stats: card.stats,
            bottleneckBodyPart: card.bottleneckBodyPart,
            bottleneckLabel: localizedBodyPartName(
              card.bottleneckBodyPart,
              l10n,
            ),
            statColors: <BodyPart, Color>{
              for (final s in card.stats)
                s.bodyPart:
                    VitalityStateStyles.bodyPartColor[s.bodyPart] ??
                    AppColors.textDim,
            },
            statLabels: <BodyPart, String>{
              for (final s in card.stats)
                s.bodyPart: localizedBodyPartName(s.bodyPart, l10n),
            },
          ),
        ),
      );
    }

    // 3b — Body-part next rows in `activeBodyParts` order. The view-model
    // already returns them in that order; we just need to render
    // non-character entries before the character row.
    for (final row in view.nextRows) {
      if (row.title is rpg.CharacterLevelTitle) continue;
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: NextTitleRow(
            slug: row.title.slug,
            titleName: _titleName(row.title, l10n),
            accentColor: _accentColor(row.title),
            currentValue: row.currentValue,
            thresholdValue: row.thresholdValue,
            bodyPartLabel: _scopeLabel(row.title, l10n),
            isCharacterLevel: false,
          ),
        ),
      );
    }

    // 3c — Character-level next row last (mockup convention: per-track
    // motivation reads naturally, then the character-wide threshold caps
    // the region).
    for (final row in view.nextRows) {
      if (row.title is! rpg.CharacterLevelTitle) continue;
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: NextTitleRow(
            slug: row.title.slug,
            titleName: _titleName(row.title, l10n),
            accentColor: _accentColor(row.title),
            currentValue: row.currentValue,
            thresholdValue: row.thresholdValue,
            bodyPartLabel: _scopeLabel(row.title, l10n),
            isCharacterLevel: true,
          ),
        ),
      );
    }

    children.add(const SizedBox(height: 16));

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: children,
    );
  }
}

/// Region header for one of the three Titles screen regions.
///
/// `cluster_semantics_identifier_pair_rule`: every identifier-bearing
/// wrapper carries `container: true` so Flutter web's AOM emits a
/// flt-semantics node even though the header itself has no role or action.
class _RegionHeader extends StatelessWidget {
  const _RegionHeader({required this.label, required this.identifier});

  final String label;
  final String identifier;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      identifier: identifier,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          label.toUpperCase(),
          style: AppTextStyles.label.copyWith(
            fontSize: 11,
            color: AppColors.textDim,
            letterSpacing: 0.12 * 11,
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// File-private helpers: title → display strings + accent color
// ───────────────────────────────────────────────────────────────────────────

/// Localized display name for a title. Falls back to the slug if the copy
/// table doesn't carry an entry for the slug (defensive; the catalog ships
/// with full coverage and the repository's parse step would have failed if
/// a slug were missing).
String _titleName(rpg.Title title, AppLocalizations l10n) {
  return localizedTitleCopy(title.slug, l10n)?.name ?? title.slug;
}

/// Scope label rendered next to the threshold: body-part name for
/// [BodyPartTitle], the localized "Personagem"/"Character" label for
/// [CharacterLevelTitle]. Cross-build titles don't use this on the
/// equipped/earned rows (they go into the dedicated [CrossBuildCard]
/// surface), but the helper returns the localized cross-build distinction
/// copy for completeness.
String _scopeLabel(rpg.Title title, AppLocalizations l10n) {
  return switch (title) {
    rpg.BodyPartTitle(:final bodyPart) => localizedBodyPartName(bodyPart, l10n),
    rpg.CharacterLevelTitle() => l10n.titlesCharacterLabel,
    rpg.CrossBuildTitle() => l10n.titlesRowCrossBuild,
  };
}

/// Threshold label rendered on the equipped/earned rows after the scope
/// label. "Rank 5" / "Nível 10" per title kind. Cross-build titles aren't
/// expected to land in [EquippedTitleCard]/[EarnedTitleRow] today (they
/// don't have a numeric threshold), but the helper returns the localized
/// distinction copy as a safe default.
String _thresholdLabel(rpg.Title title, AppLocalizations l10n) {
  return switch (title) {
    rpg.BodyPartTitle(:final rankThreshold) => l10n.titlesRowRankThreshold(
      rankThreshold,
    ),
    rpg.CharacterLevelTitle(:final levelThreshold) =>
      l10n.titlesRowCharacterLevel(levelThreshold),
    rpg.CrossBuildTitle() => l10n.titlesRowCrossBuild,
  };
}

/// Body-part hue for the row dot / progress bar fill. Character-level
/// titles use the brand violet (the "personagem" scope feeds back into the
/// shared character track, not any single body part). Cross-build titles
/// use heroGold — these titles only surface through [CrossBuildCard] (which
/// is whitelisted to read heroGold directly), so this path is defensive
/// rather than load-bearing.
Color _accentColor(rpg.Title title) {
  return switch (title) {
    rpg.BodyPartTitle(:final bodyPart) =>
      VitalityStateStyles.bodyPartColor[bodyPart] ?? AppColors.textDim,
    rpg.CharacterLevelTitle() => AppColors.primaryViolet,
    rpg.CrossBuildTitle() => AppColors.textDim,
  };
}

// ───────────────────────────────────────────────────────────────────────────
// Loading + error states
// ───────────────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(color: AppColors.textDim),
        ),
      ),
    );
  }
}

/// Branded skeleton shown while the catalog and/or earned-titles providers
/// are loading. Mirrors the 26d three-region shape: a region-header
/// placeholder followed by three rows of placeholders, repeated three
/// times. Keeping the placeholder layout aligned with the real screen
/// prevents the "shift on data arrival" feel.
class _TitlesSkeleton extends StatelessWidget {
  const _TitlesSkeleton();

  // Hoisted out of `build` (review-style: avoid reallocating placeholder
  // closures per rebuild). Both placeholders are stateless and capture
  // nothing, so static methods are the cheapest scoping option.
  static Widget _rowPlaceholder() => Container(
    height: 56,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
    decoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(kRadiusSm),
    ),
  );

  static Widget _regionHeaderPlaceholder() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Container(
      height: 14,
      width: 96,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        for (var region = 0; region < 3; region++) ...[
          _regionHeaderPlaceholder(),
          for (var i = 0; i < 3; i++) _rowPlaceholder(),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}
