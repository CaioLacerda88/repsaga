import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../routines/models/routine.dart';
import '../../../routines/providers/notifiers/routine_list_notifier.dart';
import '../../../routines/ui/widgets/routine_action_sheet.dart';
import '../../../weekly_plan/data/models/weekly_plan.dart';
import '../../../weekly_plan/providers/weekly_plan_provider.dart';

/// Phase 26f Home bucket chip row — replaces the deleted 7-day-timeline
/// `WeekBucketSection` with a chip-row layout that wraps.
///
/// Structure (top-to-bottom):
///   1. Header — `"ESTA SEMANA"` label (hotViolet, label-case) on the left
///      + `"<N> dias treinados"` progress counter on the right. The counter
///      reflects UNIQUE completion DAYS, not completed-routine count — two
///      workouts finished on the same Monday count as one day.
///   2. Chip wrap — one chip per bucket entry. Planned chips first
///      (sorted by `BucketRoutine.order` ascending), then spontaneous
///      entries appended in completion order. Wraps to multiple rows;
///      each chip is `InkWell`-tappable and opens the existing routine
///      action sheet (the closest pre-workout-preview surface in this
///      codebase). The action sheet exposes Start without auto-starting
///      the workout — preserves the PROJECT.md §3 26f acceptance criterion
///      that the chip is a preview, not a one-tap CTA.
///   3. Footer — `"EDITAR PLANO →"` link right-aligned, routes to
///      `/plan/week`. ALWAYS visible (DECISION LOCKED 2026-05-18 in
///      `docs/WIP.md`) — surfaces the plan editor even for empty-bucket
///      users with routines-but-no-plan.
///
/// Empty bucket (`plan == null` or `routines.isEmpty`) renders the
/// compact two-line variant: header + footer link, no chip Wrap.
///
/// **L10n strategy.** Single-use widget mounted only on the home screen —
/// reads [AppLocalizations.of] inline. See
/// `feedback_widget_l10n_parameterization`: reusable widgets take
/// localized strings as constructor params; screen-bound widgets can read
/// l10n directly.
///
/// **Semantics identifiers.** Root: `home-bucket-chip-row`. Each chip:
/// `home-bucket-chip-<routineId>`. Edit-plan link: `home-edit-plan-link`.
/// Identifiers carry the `routineId` (not the name) so E2E selectors are
/// stable across locale changes and routine renames.
class BucketChipRow extends ConsumerWidget {
  const BucketChipRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(weeklyPlanProvider).value;
    final routines = ref.watch(routineListProvider).value ?? const [];

    final bucket = plan?.routines ?? const <BucketRoutine>[];
    final uniqueDays = _uniqueCompletionDays(bucket);

    final nameMap = <String, String>{for (final r in routines) r.id: r.name};
    final routineMap = <String, Routine>{for (final r in routines) r.id: r};

    final orderedChips = _orderForRender(bucket);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'home-bucket-chip-row',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            title: l10n.homeBucketSectionTitle,
            progressText: l10n.homeBucketDaysTrained(uniqueDays),
          ),
          if (orderedChips.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ChipWrap(
              entries: orderedChips,
              nameMap: nameMap,
              routineMap: routineMap,
              locale: l10n.localeName,
            ),
          ],
          const SizedBox(height: 10),
          _EditPlanLink(label: l10n.homeEditPlanLink),
        ],
      ),
    );
  }

  /// Unique LOCAL-date completion-day count derived from `completedAt`.
  ///
  /// Two workouts finished on the same calendar day (local time) count
  /// as one. The header progress uses this — NOT the total number of
  /// completed routines.
  static int _uniqueCompletionDays(List<BucketRoutine> bucket) {
    final days = <DateTime>{};
    for (final r in bucket) {
      final at = r.completedAt;
      if (at == null) continue;
      final local = at.toLocal();
      days.add(DateTime(local.year, local.month, local.day));
    }
    return days.length;
  }

  /// Returns chips in render order: planned (by `order` ascending) then
  /// spontaneous (by `completedAt` ascending — completion order). Spontaneous
  /// entries without a `completedAt` (defensive — shouldn't happen since
  /// they're created server-side when a workout saves) fall back to `order`.
  static List<BucketRoutine> _orderForRender(List<BucketRoutine> bucket) {
    final planned = bucket.where((r) => !r.isSpontaneous).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final spontaneous = bucket.where((r) => r.isSpontaneous).toList()
      ..sort((a, b) {
        final ac = a.completedAt;
        final bc = b.completedAt;
        if (ac != null && bc != null) return ac.compareTo(bc);
        if (ac != null) return -1;
        if (bc != null) return 1;
        return a.order.compareTo(b.order);
      });
    return [...planned, ...spontaneous];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.progressText});

  final String title;
  final String progressText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title.toUpperCase(),
            style: AppTextStyles.label.copyWith(
              fontSize: 10,
              color: AppColors.hotViolet,
              letterSpacing: 0.14 * 10,
            ),
          ),
          Text(
            progressText,
            style: AppTextStyles.bodySmall.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textDim,
              letterSpacing: 0.06 * 10,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({
    required this.entries,
    required this.nameMap,
    required this.routineMap,
    required this.locale,
  });

  final List<BucketRoutine> entries;
  final Map<String, String> nameMap;
  final Map<String, Routine> routineMap;
  final String locale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final entry in entries)
            _BucketChip(
              entry: entry,
              routineName: nameMap[entry.routineId] ?? '—',
              routine: routineMap[entry.routineId],
              locale: locale,
            ),
        ],
      ),
    );
  }
}

class _BucketChip extends ConsumerWidget {
  const _BucketChip({
    required this.entry,
    required this.routineName,
    required this.routine,
    required this.locale,
  });

  final BucketRoutine entry;
  final String routineName;
  final Routine? routine;
  final String locale;

  bool get _isDone => entry.completedWorkoutId != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final borderColor = _isDone
        ? (entry.isSpontaneous
              ? AppColors.hotViolet.withValues(alpha: 0.30)
              : AppColors.success.withValues(alpha: 0.30))
        : AppColors.hair;

    final dayLabel = _isDone
        ? _shortDayLabel(entry.completedAt!, locale)
        : null;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'home-bucket-chip-${entry.routineId}',
      button: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 96, maxWidth: 130),
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: borderColor),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: routine == null
                ? null
                : () => showRoutineActionSheet(context, ref, routine!),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ChipStatusIcon(
                    isDone: _isDone,
                    isSpontaneous: entry.isSpontaneous,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      routineName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.label.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.02 * 11,
                        color: _isDone
                            ? AppColors.textCream
                            : AppColors.textDim,
                      ),
                    ),
                  ),
                  if (entry.isSpontaneous && _isDone) ...[
                    const SizedBox(width: 2),
                    Text(
                      '★',
                      style: AppTextStyles.label.copyWith(
                        fontSize: 9,
                        color: AppColors.hotViolet,
                      ),
                    ),
                  ],
                  if (dayLabel != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      dayLabel,
                      style: AppTextStyles.label.copyWith(
                        fontSize: 9,
                        color: AppColors.textDim,
                        letterSpacing: 0.04 * 9,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 3-letter localized weekday label ("Mon"/"Seg", "Tue"/"Ter", …),
  /// uppercased per mockup. Same `DateFormat.E(locale)` pattern as
  /// `week_plan_screen.dart::_shortDayLabel`.
  static String _shortDayLabel(DateTime completedAt, String locale) {
    final local = completedAt.toLocal();
    final raw = DateFormat.E(locale).format(local);
    final trimmed = raw.endsWith('.') ? raw.substring(0, raw.length - 1) : raw;
    return trimmed.toUpperCase();
  }
}

class _ChipStatusIcon extends StatelessWidget {
  const _ChipStatusIcon({required this.isDone, required this.isSpontaneous});

  final bool isDone;
  final bool isSpontaneous;

  @override
  Widget build(BuildContext context) {
    if (!isDone) {
      // Pending — outline ring in hotViolet (mockup: 1.5px solid hot-violet).
      return Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.hotViolet, width: 1.5),
        ),
      );
    }
    final fill = isSpontaneous ? AppColors.hotViolet : AppColors.success;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
      alignment: Alignment.center,
      child: const Icon(Icons.check, size: 10, color: AppColors.abyss),
    );
  }
}

class _EditPlanLink extends StatelessWidget {
  const _EditPlanLink({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: 'home-edit-plan-link',
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => context.push('/plan/week'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                label.toUpperCase(),
                style: AppTextStyles.label.copyWith(
                  fontSize: 10,
                  color: AppColors.hotViolet,
                  letterSpacing: 0.12 * 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
