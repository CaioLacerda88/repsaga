import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/muscle_group_body_part.dart';
import '../../../core/utils/enum_l10n.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/async_value_builder.dart';
import '../models/exercise.dart';
import '../providers/exercise_providers.dart';

class ExerciseListScreen extends ConsumerStatefulWidget {
  const ExerciseListScreen({super.key});

  @override
  ConsumerState<ExerciseListScreen> createState() => _ExerciseListScreenState();
}

class _ExerciseListScreenState extends ConsumerState<ExerciseListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).state = value.trim();
    });
  }

  void _clearFilters() {
    ref.read(selectedMuscleGroupProvider.notifier).state = null;
    ref.read(selectedEquipmentTypeProvider.notifier).state = null;
    ref.read(searchQueryProvider.notifier).state = '';
    _searchController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exercises = ref.watch(filteredExerciseListProvider);

    return Scaffold(
      // Phase 32 PR 32e scope add — align the Exercises title to the
      // standard AppBar pattern used by Saga, History, and Profile
      // Settings. Previously a raw `Text(28sp)` lived inside a `Padding`
      // tile at the top of the body, bypassing the theme's
      // `appBarTitle` token (Rajdhani 600 18sp centered, defined in
      // `app_theme.dart`). The inline 28sp + ad-hoc padding diverged
      // from the rest of the top-level surfaces and lost the
      // hairline divider + leading-affordance scaffolding that an
      // AppBar normally owns. Conversion drops the fontSize override
      // entirely and lets the theme resolve typography.
      appBar: AppBar(
        title: Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: 'exercise-list-heading',
          child: Text(l10n.exercises),
        ),
      ),
      body: SafeArea(
        // AppBar owns the top inset (status bar + toolbar height); the
        // body's SafeArea only needs to defend bottom + horizontal
        // edges. Without `top: false` the SafeArea adds redundant top
        // padding beneath the AppBar.
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 16),
            const _MuscleGroupSelector(),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SearchBar(
                controller: _searchController,
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(height: 12),
            const _EquipmentFilter(),
            const SizedBox(height: 8),
            Expanded(
              child: AsyncValueBuilder<List<Exercise>>(
                value: exercises,
                data: (list) {
                  if (list.isEmpty) {
                    final hasFilters =
                        ref.read(selectedMuscleGroupProvider) != null ||
                        ref.read(selectedEquipmentTypeProvider) != null ||
                        ref.read(searchQueryProvider).isNotEmpty;
                    return _EmptyState(
                      hasFilters: hasFilters,
                      onClearFilters: _clearFilters,
                    );
                  }
                  return _ExerciseList(
                    exercises: list,
                    onRefresh: () async {
                      // Invalidate the underlying family, not just the thin
                      // wrapper, so all cached filter combinations are cleared
                      // and a fresh Supabase query is issued (F2 fix).
                      ref.invalidate(exerciseListProvider);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Self-contained filter selector that watches its own state provider (F3 fix).
///
/// Previously the parent build() passed `ref.watch(selectedMuscleGroupProvider)`
/// as a constructor arg, causing the entire ExerciseListScreen to rebuild on
/// every muscle-group tap. Now only this widget rebuilds.
class _MuscleGroupSelector extends ConsumerWidget {
  const _MuscleGroupSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedMuscleGroupProvider);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      height: 72,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _MuscleGroupButton(
              label: l10n.all,
              // "All" is a UI meta-filter with no matching pixel asset; a
              // Material icon is the correct affordance here. No body-part
              // hue applies — the "All" filter spans every group.
              icon: const Icon(Icons.grid_view_rounded, size: 24, weight: 600),
              hueColor: null,
              isSelected: selected == null,
              onTap: () {
                ref.read(selectedMuscleGroupProvider.notifier).state = null;
              },
              theme: theme,
            ),
            ...MuscleGroup.values.map(
              (group) => _MuscleGroupButton(
                label: group.localizedName(l10n),
                icon: AppIcons.render(group.svgIcon, size: 24),
                // Phase 27 L7 — propagate the Phase 26a body-part hue
                // tokens to the Exercises tab. Six strength pillars get
                // their identity hue; cardio falls back to neutral via
                // null. See feedback_design_token_sweep_on_new_tokens.
                hueColor: group.hueColor,
                isSelected: selected == group,
                onTap: () {
                  ref.read(selectedMuscleGroupProvider.notifier).state = group;
                },
                theme: theme,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MuscleGroupButton extends StatelessWidget {
  const _MuscleGroupButton({
    required this.label,
    required this.icon,
    required this.hueColor,
    required this.isSelected,
    required this.onTap,
    required this.theme,
  });

  final String label;

  /// Pre-sized 24dp icon widget. The "All" meta-filter renders a Material
  /// [Icon] (`Icons.grid_view_rounded`); real muscle groups render their
  /// [MuscleGroup.svgIcon] via [AppIcons.render].
  final Widget icon;

  /// Body-part identity hue for this muscle group, resolved via
  /// `core/theme/muscle_group_body_part.dart`. Non-null for the six v1
  /// strength pillars (chest, back, legs, shoulders, arms, core), null
  /// for "All" and cardio. When null the button falls back to the
  /// neutral primary/onSurface palette (Phase 27 L7).
  final Color? hueColor;
  final bool isSelected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final primary = theme.colorScheme.primary;
    // Identity-color resolution (Phase 27 L7):
    //   * Selected + has hue → full hue.
    //   * Unselected + has hue → hue at 60% alpha (mirrors the dim/active
    //     contrast used on Saga's BodyPartRankRow dots and the Stats
    //     trend-chart ghost lines).
    //   * No hue → neutral primary/onSurface fallback (pre-L7 behaviour
    //     preserved for "All" and cardio).
    final iconColor = hueColor != null
        ? (isSelected ? hueColor! : hueColor!.withValues(alpha: 0.60))
        : (isSelected ? primary : theme.colorScheme.onSurface);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        container: true,
        identifier:
            'exercise-filter-${label.toLowerCase().replaceAll(' ', '-')}',
        label: '$label muscle group filter',
        selected: isSelected,
        child: Material(
          color: isSelected
              ? primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(minHeight: 64, minWidth: 72),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: IconTheme(
                      data: IconThemeData(color: iconColor, size: 24),
                      child: icon,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    // [AppTextStyles.label] = Inter 600 11dp with +0.12em
                    // tracking — chip register. Color stays on the neutral
                    // primary/onSurface pair since body-part identity is on
                    // the icon; tinting the text too would overload the chip.
                    style: AppTextStyles.label.copyWith(
                      color: isSelected ? primary : theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      identifier: 'exercise-list-search',
      label: l10n.searchExercisesSemantics,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: l10n.searchExercises,
          prefixIcon: const Icon(Icons.search_rounded, weight: 600),
        ),
      ),
    );
  }
}

/// Self-contained equipment filter that watches its own state provider (F3 fix).
///
/// Same rationale as [_MuscleGroupSelector] — isolates rebuilds so the parent
/// ExerciseListScreen does not rebuild when equipment type changes.
class _EquipmentFilter extends ConsumerWidget {
  const _EquipmentFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedEquipmentTypeProvider);
    final theme = Theme.of(context);

    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: EquipmentType.values.map((type) {
            final isSelected = selected == type;
            final l10n = AppLocalizations.of(context);
            final typeName = type.localizedName(l10n);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                container: true,
                identifier: 'exercise-equip-${type.name}',
                label: '$typeName equipment filter',
                selected: isSelected,
                child: FilterChip(
                  avatar: AppIcons.render(type.svgIcon, size: 18),
                  label: Text(typeName),
                  selected: isSelected,
                  onSelected: (val) {
                    ref.read(selectedEquipmentTypeProvider.notifier).state = val
                        ? type
                        : null;
                  },
                  selectedColor: theme.colorScheme.primary.withValues(
                    alpha: 0.15,
                  ),
                  checkmarkColor: theme.colorScheme.primary,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ExerciseList extends StatelessWidget {
  const _ExerciseList({required this.exercises, required this.onRefresh});

  final List<Exercise> exercises;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: exercises.length,
        itemBuilder: (context, index) =>
            _ExerciseCard(exercise: exercises[index]),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    // P9: a 3dp left-border accent in primary flags user-created exercises
    // in the browse list so they are instantly distinguishable from the 150
    // default rows. Default cards keep the existing hairline top-border only.
    final isCustom = !exercise.isDefault;

    return Semantics(
      label: AppLocalizations.of(context).exerciseItemSemantics(exercise.name),
      button: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.go('/exercises/${exercise.id}'),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                // P9: no borderRadius here — Flutter requires uniform Border
                // colors when borderRadius is set, but we need the top hairline
                // and the primary left accent to differ. The outer Material's
                // borderRadius + clipBehavior round the visible corners.
                border: Border(
                  top: BorderSide(color: primary.withValues(alpha: 0.15)),
                  left: isCustom
                      ? BorderSide(color: primary, width: 3)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(exercise.name, style: AppTextStyles.title),
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final l10n = AppLocalizations.of(context);
                            return Wrap(
                              spacing: 8,
                              children: [
                                _InfoChip(
                                  label: exercise.muscleGroup.localizedName(
                                    l10n,
                                  ),
                                  svgIcon: exercise.muscleGroup.svgIcon,
                                  // Phase 27 L7 — muscle-group chip carries
                                  // the body-part hue identity. Null for
                                  // cardio / future non-pillar groups → chip
                                  // falls back to the neutral onSurface tint.
                                  iconColor: exercise.muscleGroup.hueColor,
                                ),
                                _InfoChip(
                                  label: exercise.equipmentType.localizedName(
                                    l10n,
                                  ),
                                  svgIcon: exercise.equipmentType.svgIcon,
                                  // Equipment is not a body-part axis — keep
                                  // it on the neutral tint so the muscle-
                                  // group hue is the only identity signal in
                                  // the chip row.
                                  iconColor: null,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    weight: 600,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.svgIcon,
    required this.iconColor,
  });

  final String label;

  /// Inline-SVG glyph string from [AppMuscleIcons] / [AppEquipmentIcons] (or
  /// the reused [AppIcons.lift] for barbell). Rendered via [AppIcons.render]
  /// so a single asset recolors with the theme.
  final String svgIcon;

  /// Optional identity hue for the icon (Phase 27 L7). Non-null on the
  /// muscle-group chip when the group maps to one of the six v1 body-
  /// part identities (chest, back, legs, shoulders, arms, core); null
  /// for cardio + the equipment-type chip, both of which fall back to
  /// the neutral 0.75-alpha onSurface tint.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveIconColor =
        iconColor ?? theme.colorScheme.onSurface.withValues(alpha: 0.75);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcons.render(svgIcon, size: 16, color: effectiveIconColor),
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.label.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilters, required this.onClearFilters});

  final bool hasFilters;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcons.render(
              hasFilters ? AppIcons.search : AppIcons.lift,
              size: 64,
              color: AppColors.textDim,
            ),
            const SizedBox(height: 16),
            Semantics(
              container: true,
              identifier: hasFilters
                  ? 'exercise-list-empty-filtered'
                  : 'exercise-list-empty-no-filter',
              child: Text(
                hasFilters
                    ? l10n.noExercisesMatchFilters
                    : l10n.yourExercisesWillAppear,
                style: AppTextStyles.title,
                textAlign: TextAlign.center,
              ),
            ),
            // Phase 32 PR 32h retired the user-create-exercise surface — the
            // no-filter empty state collapses to icon + heading only. The
            // seeded default exercises ship with the app, so an unfiltered
            // empty state is only reachable via the cache schema migration
            // path (and self-recovers on next online fetch). The filtered
            // branch keeps its "Clear Filters" affordance.
            if (hasFilters) ...[
              const SizedBox(height: 16),
              Semantics(
                container: true,
                identifier: 'exercise-list-clear-filters',
                child: TextButton(
                  onPressed: onClearFilters,
                  child: Text(
                    l10n.clearFilters,
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
