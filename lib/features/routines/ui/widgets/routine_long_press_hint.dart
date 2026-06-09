import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../providers/routine_hint_provider.dart';

/// One-time discoverability hint for the routine-card long-press gesture
/// (long-press → edit/delete action sheet).
///
/// Rendered as a peer of the routine list — placed BETWEEN the "MY ROUTINES"
/// `SectionHeader` and the first `RoutineCard` — rather than on the card
/// itself, so it never collides with the card's play affordance. Pure ambient
/// list-metadata: a 16dp [Icons.touch_app] glyph + a single 12sp Barlow line,
/// both [AppColors.textDim], left-aligned to the 16dp card edge. No card,
/// border, or background.
///
/// **Self-gating.** This widget owns the show/hide decision via
/// [routineHintProvider]: it records one surface view on mount and renders
/// nothing once the gesture has been discovered or the view cap is reached.
/// Both render surfaces (the `/routines` list and the home routine section)
/// drop it in unconditionally and let it decide.
///
/// The localized hint string is passed in (not resolved via
/// `AppLocalizations.of(context)`) so the widget stays l10n-harness-free in
/// unit tests — the screen layer supplies `l10n.hintRoutineLongPress`.
class RoutineLongPressHint extends ConsumerStatefulWidget {
  const RoutineLongPressHint({
    required this.label,
    this.horizontalPadding = 16,
    super.key,
  });

  /// Localized hint copy, e.g. `l10n.hintRoutineLongPress`.
  final String label;

  /// Left/right inset so the hint's `Icons.touch_app` glyph lines up with the
  /// 16dp left edge of the routine cards on the given surface.
  ///
  /// On `/routines` the cards live inside their own `SliverPadding(16)` while
  /// this hint is an unpadded sliver peer, so it needs its own 16dp inset
  /// (the default). On the home screen the whole routine section already sits
  /// inside the page's 16dp horizontal padding, so the cards start at x=16
  /// with no extra inset — pass `0` there so the hint aligns to the same edge
  /// instead of doubling to x=32.
  final double horizontalPadding;

  @override
  ConsumerState<RoutineLongPressHint> createState() =>
      _RoutineLongPressHintState();
}

class _RoutineLongPressHintState extends ConsumerState<RoutineLongPressHint> {
  @override
  void initState() {
    super.initState();
    // Defer the view-count increment to the next frame: mutating provider
    // state synchronously during the first build of a subtree is unsafe
    // (cascading rebuild ordering). The post-frame callback guarantees the
    // mount has settled before we touch Hive + emit new state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(routineHintProvider.notifier).recordView();
    });
  }

  @override
  Widget build(BuildContext context) {
    final shouldShow = ref.watch(routineHintProvider);
    if (!shouldShow) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.horizontalPadding,
        0,
        widget.horizontalPadding,
        8,
      ),
      child: Semantics(
        container: true,
        identifier: 'routine-longpress-hint',
        child: Row(
          children: [
            const Icon(Icons.touch_app, size: 16, color: AppColors.textDim),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                widget.label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
