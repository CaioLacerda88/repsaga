import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/section_header.dart';
import 'widgets/routine_action_sheet.dart';
import '../providers/notifiers/routine_list_notifier.dart';
import 'start_routine_action.dart';
import 'widgets/routine_card.dart';

class RoutineListScreen extends ConsumerWidget {
  const RoutineListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final routinesAsync = ref.watch(routineListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          container: true,
          identifier: 'routine-heading',
          child: Text(l10n.routines),
        ),
        actions: [
          Semantics(
            container: true,
            identifier: 'routine-mgmt-create-btn',
            child: IconButton(
              icon: const Icon(Icons.add),
              tooltip: l10n.createRoutine,
              onPressed: () => context.go('/routines/create'),
            ),
          ),
        ],
      ),
      body: routinesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.failedToLoadRoutines,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () =>
                    ref.read(routineListProvider.notifier).refresh(),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
        data: (routines) {
          final userRoutines = routines.where((r) => r.userId != null).toList();
          final defaultRoutines = routines.where((r) => r.isDefault).toList();

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
                sliver: SliverToBoxAdapter(
                  child: SectionHeader(
                    title: l10n.myRoutinesSection,
                    semanticsIdentifier: 'routine-my-section',
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              if (userRoutines.isEmpty)
                SliverToBoxAdapter(
                  child: _CustomRoutinesEmptyState(
                    onCreateTap: () => context.go('/routines/create'),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: userRoutines.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RoutineCard(
                        routine: userRoutines[index],
                        onTap: () => startRoutineWorkout(
                          context,
                          ref,
                          userRoutines[index],
                        ),
                        onLongPress: () => showRoutineActionSheet(
                          context,
                          ref,
                          userRoutines[index],
                        ),
                      ),
                    ),
                  ),
                ),

              if (defaultRoutines.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: SectionHeader(
                      title: l10n.starterRoutinesSection,
                      semanticsIdentifier: 'routine-starter-section',
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: defaultRoutines.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RoutineCard(
                        routine: defaultRoutines[index],
                        onTap: () => startRoutineWorkout(
                          context,
                          ref,
                          defaultRoutines[index],
                        ),
                        onLongPress: () => showRoutineActionSheet(
                          context,
                          ref,
                          defaultRoutines[index],
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              // Bottom padding for safe area / FAB clearance.
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          );
        },
      ),
    );
  }
}

/// BUG-029: branded empty state for the "MY ROUTINES" section. The previous
/// implementation was a single dim line of text pointing at the AppBar `+`
/// icon — easy to miss on first launch. This version adds a 56dp brand
/// glyph (the routines plan icon, also used in the bottom nav bar) plus an
/// inline `FilledButton` that navigates to `/routines/create` so the
/// primary action is right under the user's thumb instead of buried in the
/// AppBar.
class _CustomRoutinesEmptyState extends StatelessWidget {
  const _CustomRoutinesEmptyState({required this.onCreateTap});

  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Semantics(
        container: true,
        identifier: 'routines-empty-state',
        child: Column(
          children: [
            Opacity(
              opacity: 0.6,
              child: AppIcons.render(
                AppIcons.plan,
                color: AppColors.hotViolet,
                size: 56,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.routinesEmptyTitle,
              style: AppTextStyles.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.routinesEmptyBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textDim,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Semantics(
              container: true,
              identifier: 'routines-empty-create-btn',
              button: true,
              child: FilledButton.icon(
                onPressed: onCreateTap,
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.routinesEmptyCta),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
