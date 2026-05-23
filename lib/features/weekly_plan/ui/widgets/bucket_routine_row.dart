import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Compact bucket-entry row used by the plan editor (~42dp min-height).
///
/// States:
///   * Planned (not done) — outline-ring icon, name in textDim.
///   * Done planned — green-filled check, name in textCream, completion-day
///     meta on the right.
///   * Done spontaneous — violet-filled check + ★ tag, name in textCream,
///     completion-day meta on the right.
///
/// The drag handle from the previous `PlanRoutineRow` is removed — the new
/// design uses long-press-to-drag via ReorderableListView's default
/// behavior, no visible affordance needed at 42dp height.
///
/// [spontaneousLabel] is passed in by the screen layer (resolved from
/// `AppLocalizations.spontaneousTag` at the call site) so this widget stays
/// presentation-pure and unit-testable without an `AppLocalizations` harness.
/// It MUST be supplied whenever [isSpontaneous] is true.
class BucketRoutineRow extends StatelessWidget {
  const BucketRoutineRow({
    super.key,
    required this.routineId,
    required this.name,
    required this.isDone,
    required this.isSpontaneous,
    this.completionDayLabel,
    this.spontaneousLabel,
    this.onOverflowTap,
  });

  /// `null` for a spontaneous bucket entry whose source routine was deleted
  /// or never existed (free workout — see migration 00063 + `BucketRoutine`).
  /// The Semantics identifier falls back to `bucket-row-spontaneous` in that
  /// case so the row still has a deterministic test handle.
  final String? routineId;
  final String name;
  final bool isDone;
  final bool isSpontaneous;

  /// Localized 3-letter weekday tag ("Seg", "Ter", …). Null when not done.
  final String? completionDayLabel;

  /// Localized "spontaneous" label (e.g. "Espontâneo" in pt, "Spontaneous"
  /// in en). Falls back to a literal "Spontaneous" string only if the
  /// caller forgot to pass it while [isSpontaneous] is true.
  final String? spontaneousLabel;

  final VoidCallback? onOverflowTap;

  @override
  Widget build(BuildContext context) {
    final identifierSuffix = routineId ?? 'spontaneous';
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'bucket-row-$identifierSuffix',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _StatusIcon(isDone: isDone, isSpontaneous: isSpontaneous),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      // L15: routine names in the bucket → Rajdhani per
                      // mockup `.routine-name { font-family: 'Rajdhani'; }`.
                      // See project_design_language_typography.
                      style: AppTextStyles.headline.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDone ? AppColors.textCream : AppColors.textDim,
                      ),
                    ),
                  ),
                  if (isSpontaneous && isDone) ...[
                    const SizedBox(width: 8),
                    _SpontaneousTag(label: spontaneousLabel ?? 'Spontaneous'),
                  ],
                ],
              ),
            ),
            if (isDone && completionDayLabel != null) ...[
              Text(
                completionDayLabel!,
                style: AppTextStyles.numeric.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDim,
                ),
              ),
              const SizedBox(width: 12),
            ],
            // L6 — the row maps `onOverflowTap` straight to `_removeRoutine`
            // (no menu, no disambiguation). The legacy `Icons.more_horiz`
            // glyph wrongly implied a popup would open. `Icons.close` makes
            // the direct-remove affordance honest. The Semantics identifier
            // is kept as `bucket-row-overflow-$routineId` so E2E selectors
            // and the IconButton's ValueKey stay stable across the swap.
            Semantics(
              container: true,
              explicitChildNodes: true,
              button: true,
              identifier: 'bucket-row-overflow-$identifierSuffix',
              child: IconButton(
                key: const ValueKey('bucket-row-overflow'),
                icon: const Icon(Icons.close, size: 20),
                color: AppColors.textDim,
                visualDensity: VisualDensity.compact,
                onPressed: onOverflowTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.isDone, required this.isSpontaneous});

  final bool isDone;
  final bool isSpontaneous;

  @override
  Widget build(BuildContext context) {
    const size = 20.0;

    if (!isDone) {
      return Container(
        key: const ValueKey('bucket-row-status-planned'),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.hotViolet, width: 1.5),
        ),
      );
    }

    final fillColor = isSpontaneous ? AppColors.hotViolet : AppColors.success;
    final key = isSpontaneous
        ? const ValueKey('bucket-row-status-done-spontaneous')
        : const ValueKey('bucket-row-status-done');

    return Container(
      key: key,
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: fillColor),
      child: const Icon(Icons.check, color: AppColors.textCream, size: 14),
    );
  }
}

class _SpontaneousTag extends StatelessWidget {
  const _SpontaneousTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('bucket-row-spontaneous-tag'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.hotViolet.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppTextStyles.label.copyWith(
          fontSize: 10,
          letterSpacing: 0.12 * 10,
          color: AppColors.hotViolet,
        ),
      ),
    );
  }
}
