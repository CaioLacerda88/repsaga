import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/workout_formatters.dart';
import '../../../../l10n/app_localizations.dart';
import '../../providers/workout_history_providers.dart';

/// Editorial one-liner showing the user's most recent completed session.
///
/// Replaces the old two-cell stat grid. No card chrome — a single tappable
/// line that navigates to the full workout history.
///
/// Format: `"Last: {routineName}, {relativeDate}"` (e.g. `"Last: Push Day,
/// Yesterday"`).
///
/// **Locale fix (Phase 27 L16):** the relative-date string is computed
/// HERE (with `AppLocalizations.of(context)`) rather than in
/// `lastSessionProvider`, because providers have no `BuildContext` and the
/// formatter's `l10n: null` fallback returns English ("Yesterday") regardless
/// of the user's app locale — causing the mixed-language render
/// `"Último: <routine>, Yesterday"` on pt-BR devices.
///
/// Hidden (renders `SizedBox.shrink()`) when the user has no history yet.
class LastSessionLine extends ConsumerWidget {
  const LastSessionLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final last = ref.watch(lastSessionProvider);
    if (last == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final relativeDate = WorkoutFormatters.formatRelativeDate(
      last.date,
      l10n: l10n,
    );

    return Semantics(
      container: true,
      identifier: 'home-last-session',
      button: true,
      label: l10n.lastSessionSemantics(last.name, relativeDate),
      child: InkWell(
        onTap: () => context.push('/home/history'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: l10n.lastSessionPrefix,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                TextSpan(
                  text: last.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: ', $relativeDate',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
