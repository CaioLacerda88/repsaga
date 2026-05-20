import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/radii.dart';
import '../../../l10n/app_localizations.dart';
import '../models/character_sheet_state.dart';
import '../models/vitality_state.dart';
import '../providers/character_sheet_provider.dart';
import 'utils/vitality_state_styles.dart';
import 'widgets/body_part_rank_row.dart';
import 'widgets/character_xp_bar.dart';
import 'widgets/codex_nav_row.dart';
import 'widgets/dormant_cardio_row.dart';
import 'widgets/saga_header.dart';

/// `/profile` (the "Saga" tab) character sheet.
///
/// Phase 26b Option B v4 composition: a tight three-column header plus a
/// 6dp character XP bar collapse the rune face into ~80dp of chrome, freeing
/// the screen for six trainable body-part rows + a dormant cardio row.
/// Account/preferences settings move to `/profile/settings`, reachable via
/// the gear icon in the app bar.
///
/// **Composition (top-down):**
///   1. AppBar — "Saga" title + gear icon → `/profile/settings`.
///   2. [SagaHeader] — rune halo (36dp) · LVL numeral · class + title meta.
///   3. [CharacterXpBar] — 6dp violet gradient track + remaining-to-LVL+1.
///   4. Onboarding hint — first-set-awakens banner when `isZeroHistory`.
///   5. Six [BodyPartRankRow]s — Option B v4 inline rank + mini XP bar.
///   6. [DormantCardioRow] — single distinct row.
///   7. Three [CodexNavRow]s — Stats / Titles / History.
///
/// AsyncValue handling:
///   * loading → runic skeleton (placeholder rows).
///   * error   → "abyss" empty state with retry.
///   * data    → full layout.
class CharacterSheetScreen extends ConsumerWidget {
  const CharacterSheetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sheetAsync = ref.watch(characterSheetProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sagaTabLabel),
        actions: [
          Semantics(
            container: true,
            identifier: 'saga-settings-btn',
            button: true,
            label: l10n.settingsLabel,
            child: IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: l10n.settingsLabel,
              onPressed: () => context.push('/profile/settings'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: sheetAsync.when(
          data: (sheet) => _CharacterSheetBody(sheet: sheet),
          loading: () => const _CharacterSheetSkeleton(),
          error: (err, _) => _CharacterSheetError(
            onRetry: () => ref.invalidate(characterSheetProvider),
          ),
        ),
      ),
    );
  }
}

class _CharacterSheetBody extends StatelessWidget {
  const _CharacterSheetBody({required this.sheet});

  final CharacterSheetState sheet;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Semantics(
        container: true,
        identifier: 'character-sheet',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            SagaHeader(
              haloState: sheet.haloState,
              characterLevel: sheet.characterLevel,
              characterClass: sheet.characterClass,
              activeTitle: sheet.activeTitle,
            ),
            const SizedBox(height: 12),
            // Day-zero ordering: welcoming banner sits between header and bar
            // so the user reads "welcome → first set will awaken → your goal
            // (the bar)". On non-zero history the banner is omitted and the
            // bar follows the header directly.
            if (sheet.isZeroHistory) ...[
              const _FirstSetAwakensBanner(),
              const SizedBox(height: 12),
            ],
            CharacterXpBar(
              lifetimeXp: sheet.lifetimeXp,
              xpForNextLevel: sheet.xpForNextLevel,
              characterLevel: sheet.characterLevel,
            ),
            const SizedBox(height: 16),
            // BodyPartRankRow emits its OWN Semantics(container, button,
            // identifier) wrapper directly around the inner InkWell — this is
            // load-bearing because Flutter web's AOM bridge only forwards
            // Playwright clicks to the gesture detector when the Semantics
            // node and the InkWell live in the same build() method (one
            // SemanticsNode boundary). Wrapping it externally here meant the
            // SemanticsNode and the InkWell were on separate nodes; the AOM
            // dispatched the click to the outer (gesture-less) node, so
            // onTap never fired even though `button: true` was set. The
            // proven-working pattern from `vitality_table.dart` is to colocate
            // the Semantics + InkWell in one build method. Cluster:
            // semantics-identifier-pair-rule.
            for (final entry in sheet.bodyPartProgress)
              BodyPartRankRow(entry: entry),
            const SizedBox(height: 16),
            Semantics(
              container: true,
              identifier: 'dormant-cardio-row',
              child: const DormantCardioRow(),
            ),
            const SizedBox(height: 24),
            const _CodexNavSection(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _FirstSetAwakensBanner extends StatelessWidget {
  const _FirstSetAwakensBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
            color: AppColors.primaryViolet.withValues(alpha: 0.4),
          ),
          borderRadius: BorderRadius.circular(kRadiusMd),
        ),
        child: Semantics(
          container: true,
          identifier: 'first-set-awakens-banner',
          child: Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                color: AppColors.hotViolet,
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.firstSetAwakensCopy,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textCream,
                    fontStyle: FontStyle.italic,
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

class _CodexNavSection extends StatelessWidget {
  const _CodexNavSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          CodexNavRow(
            label: l10n.statsDeepDiveLabel,
            semanticIdentifier: 'codex-nav-stats',
            onTap: () => context.push('/saga/stats'),
          ),
          const SizedBox(height: 8),
          CodexNavRow(
            label: l10n.titlesLabel,
            semanticIdentifier: 'codex-nav-titles',
            onTap: () => context.push('/saga/titles'),
          ),
          const SizedBox(height: 8),
          CodexNavRow(
            label: l10n.historyLabel,
            semanticIdentifier: 'codex-nav-history',
            onTap: () => context.push('/home/history'),
          ),
        ],
      ),
    );
  }
}

class _CharacterSheetSkeleton extends StatelessWidget {
  const _CharacterSheetSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        // Bottom padding matches the live body's trailing SizedBox so the
        // skeleton placeholder rows don't sit flush against the viewport
        // edge during the loading flash.
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          children: [
            // Phase 26b: SagaHeader's three-column footprint ~64dp tall.
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(kRadiusMd),
              ),
              child: const SizedBox(height: 64),
            ),
            const SizedBox(height: 16),
            // CharacterXpBar placeholder (6dp bar + ~10dp label row).
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(kRadiusSm),
              ),
              child: const SizedBox(height: 16),
            ),
            const SizedBox(height: 24),
            // Six body-part-row placeholders (mirroring the new composition).
            for (var i = 0; i < 6; i++) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(kRadiusSm),
                ),
                child: const SizedBox(height: 56),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _CharacterSheetError extends StatelessWidget {
  const _CharacterSheetError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // BUG-026: drop generic Material error glyph in favor of the
            // brand hero sigil (dimmed) so the error state stays inside the
            // Arcane Ascent visual language.
            AppIcons.render(
              AppIcons.hero,
              // Phase 26b pattern: element-level alpha over the textDim color
              // instead of an Opacity wrapper. Avoids the compositing layer +
              // matches the BodyPartRankRow._UntrainedRow approach for visual
              // dimming. The icon is non-interactive here so the splash-bleed
              // concern doesn't apply, but consistency in the pattern wins.
              color: AppColors.textDim.withValues(alpha: 0.4),
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.error,
              style: AppTextStyles.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Use VitalityState.dormant border just to stay on-palette.
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: VitalityState.active.borderColor,
              ),
              onPressed: onRetry,
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
