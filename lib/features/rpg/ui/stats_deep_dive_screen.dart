import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../models/body_part.dart';
import '../models/stats_deep_dive_state.dart';
import '../providers/stats_provider.dart';
import 'widgets/vitality_explainer_sheet.dart';
import 'widgets/vitality_table.dart';
import 'widgets/vitality_trend_chart.dart';
import 'widgets/volume_peak_block.dart';

/// `/saga/stats` deep-dive screen.
///
/// The numeric face of the saga. The character sheet is the rune face (no
/// numbers, runes drive the visual state); this screen is where users come
/// to see the underlying figures: the 90-day (or narrower) Vitality trend,
/// the live Vitality table, and per-body-part weekly volume + peak EWMA.
///
/// **Composition:** a [statsProvider] that hydrates a [StatsDeepDiveState]
/// from rpg + xp_events. The screen is pure presentation — every section
/// reads its slice from that single state object so the X-axis, the
/// percentage column, and the trend line agree by construction.
///
/// **Selection state lives here.** The user taps a row in [VitalityTable]
/// → the screen updates [_selectedBodyPart] → [VitalityTrendChart] re-draws
/// with the new vivid line. We hold this in widget state (not a provider)
/// because it's purely transient UI focus, never persisted, and only this
/// screen reads it.
///
/// **No activity gate.** Per UX-critic amendment #1, the screen is reachable
/// from a fresh account. The empty-state copy is communicated through the
/// data shape (zero %, dormant copy, flat trend lines, empty peaks).
class StatsDeepDiveScreen extends ConsumerStatefulWidget {
  const StatsDeepDiveScreen({super.key, this.initialBodyPart});

  /// Pre-selected body part for the trend chart. When non-null, the screen
  /// opens with this body part highlighted; when null, defaults to
  /// [BodyPart.chest] per the legacy behavior. Source: the `body_part`
  /// query parameter on `/saga/stats` (set by `BodyPartRankRow` tap in 26b).
  final BodyPart? initialBodyPart;

  @override
  ConsumerState<StatsDeepDiveScreen> createState() =>
      _StatsDeepDiveScreenState();
}

class _StatsDeepDiveScreenState extends ConsumerState<StatsDeepDiveScreen> {
  /// Currently-selected body part for the trend chart. Initialized from
  /// [StatsDeepDiveScreen.initialBodyPart] in [initState], or defaults to
  /// chest — the canonical first body part in [activeBodyParts]. Re-defaults
  /// if the data shape changes such that `chest` isn't a valid pick
  /// (defensive — shouldn't happen because the provider always emits all six
  /// rows).
  late BodyPart _selectedBodyPart;

  @override
  void initState() {
    super.initState();
    // One-shot snapshot: GoRouter replaces this widget on re-navigation,
    // so didUpdateWidget would never fire for a `body_part` change in the
    // normal deep-link flow. After the initial selection, the user's row
    // taps in VitalityTable drive _selectedBodyPart via setState — the
    // prop is only consulted on first mount.
    _selectedBodyPart = widget.initialBodyPart ?? BodyPart.chest;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stateAsync = ref.watch(statsProvider);

    return Semantics(
      identifier: 'saga-stats-screen',
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.statsDeepDiveTitle)),
        body: stateAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorState(message: '$error'),
          data: (state) => _Body(
            state: state,
            selectedBodyPart: _selectedBodyPart,
            onSelectBodyPart: (bp) => setState(() => _selectedBodyPart = bp),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.selectedBodyPart,
    required this.onSelectBodyPart,
  });

  final StatsDeepDiveState state;
  final BodyPart selectedBodyPart;
  final ValueChanged<BodyPart> onSelectBodyPart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trendHeading = state.useNarrowWindow
        ? l10n.vitalityTrendHeadingShort
        : l10n.vitalityTrendHeading;
    final orderedBodyParts = activeBodyParts.toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
      children: [
        // ─── Trend chart ──────────────────────────────────────────────────
        _SectionHeader(
          label: trendHeading,
          infoIconKey: const ValueKey('vitality-trend-info-icon'),
          onInfoTap: () => _showVitalityExplainer(context),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: VitalityTrendChart(
            trendByBodyPart: state.trendByBodyPart,
            selectedBodyPart: selectedBodyPart,
            windowStart: state.windowStart,
            windowEnd: state.windowEnd,
            useNarrowWindow: state.useNarrowWindow,
          ),
        ),
        const SizedBox(height: 24),

        // ─── Live Vitality table ──────────────────────────────────────────
        // Section header anchors the chart→table junction. Without it the
        // table reads as the chart's legend; with it the table claims its
        // own register as the live current-state surface.
        _SectionHeader(
          label: l10n.liveVitalitySectionHeading,
          infoIconKey: const ValueKey('vitality-table-info-icon'),
          onInfoTap: () => _showVitalityExplainer(context),
        ),
        const SizedBox(height: 8),
        VitalityTable(
          rows: state.vitalityRows,
          selectedBodyPart: selectedBodyPart,
          onSelect: onSelectBodyPart,
        ),
        const SizedBox(height: 24),

        // ─── Volume & pico section ───────────────────────────────────────
        _SectionHeader(label: l10n.volumePeakSectionHeading),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < orderedBodyParts.length; i++) ...[
              _buildVolumePeakBlock(orderedBodyParts[i]),
              if (i < orderedBodyParts.length - 1)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.surface2,
                ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildVolumePeakBlock(BodyPart bp) {
    final row = state.volumePeakByBodyPart[bp]!;
    return VolumePeakBlock(
      bodyPart: bp,
      row: row,
      volumeDelta: VolumeDeltaView.fromRow(row),
      peakDelta: PeakDeltaView.fromRow(row),
    );
  }
}

/// Opens [VitalityExplainerSheet] as a modal bottom sheet. The sheet paints
/// its own surface (rounded top edge + scrim-friendly background) so this
/// scaffold passes a transparent background and lets `isScrollControlled`
/// give the sheet room to size to its own content.
void _showVitalityExplainer(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const VitalityExplainerSheet(),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.onInfoTap, this.infoIconKey});

  final String label;

  /// Optional handler — when non-null, a 14dp ⓘ info icon renders at the
  /// trailing edge of the header. Currently used by the trend chart and the
  /// live-vitality table headers to open [VitalityExplainerSheet]. The
  /// Volume & peak / Peak loads headers leave this null per the 26c spec
  /// (no explainer surface for those sections).
  final VoidCallback? onInfoTap;

  /// Optional `Key` for the icon's tap target. Tests anchor onto this rather
  /// than walking the widget tree by type — keeps the test resilient to
  /// future icon-shape changes (e.g. swapping `Icons.info_outline` for a
  /// custom glyph).
  final Key? infoIconKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 26c: explicit 12dp bottom padding fixes the trend chart's top label
      // clipping against this header (previously fromLTRB(16, 8, 16, 0)).
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: AppTextStyles.sectionHeader.copyWith(
                color: AppColors.hotViolet,
              ),
            ),
          ),
          if (onInfoTap != null)
            InkWell(
              key: infoIconKey,
              onTap: onInfoTap,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.info_outline,
                  size: 14,
                  color: AppColors.textDim,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

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
