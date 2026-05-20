import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';

/// Result of the resume workout dialog.
enum ResumeWorkoutResult { resume, discard }

/// Threshold past which a workout is considered "stale" and the dialog
/// surfaces an age line plus stronger copy.
const Duration _staleThreshold = Duration(hours: 6);

/// Returns true when an active workout has been idle long enough (6h+) that
/// resuming it likely means crossing a session boundary.
///
/// Exposed as a package-level function for unit testing. Kept intentionally
/// tiny so the branching in [ResumeWorkoutDialog] stays self-documenting.
bool isStaleWorkout(Duration age) => age >= _staleThreshold;

/// Human-readable age string for the stale-workout dialog body.
///
/// Rules (in order):
///   - `< 1h`              → "less than an hour ago"
///   - `>= 1h`, same day   → "$N hour(s) ago"
///   - previous calendar day (and `< 48h`) → "yesterday at H:MM AM/PM"
///   - `< 7d`              → "$WEEKDAY at H:MM AM/PM"
///   - `>= 7d`             → "$N days ago"
///
/// [now] is injected so tests can assert against a fixed clock.
/// [l10n] is optional for backward-compat with tests; when null,
/// falls back to hard-coded English.
String formatResumeAge(
  DateTime startedAt,
  DateTime now, {
  AppLocalizations? l10n,
  String? locale,
}) {
  final age = now.difference(startedAt);

  if (age < const Duration(hours: 1)) {
    return l10n?.lessThanAnHourAgo ?? 'less than an hour ago';
  }

  final startedDay = DateTime(startedAt.year, startedAt.month, startedAt.day);
  final today = DateTime(now.year, now.month, now.day);
  final dayDelta = today.difference(startedDay).inDays;

  // Same calendar day → hour count.
  if (dayDelta == 0) {
    final hours = age.inHours;
    return l10n?.hoursAgo(hours) ??
        (hours == 1 ? '1 hour ago' : '$hours hours ago');
  }

  // Previous calendar day and still within 48h → "yesterday at H:MM".
  if (dayDelta == 1 && age < const Duration(hours: 48)) {
    final clock = _formatClock(startedAt, locale: locale);
    return l10n?.yesterdayAt(clock) ?? 'yesterday at $clock';
  }

  // Within the last week → weekday name + clock.
  if (dayDelta < 7) {
    final weekday = _weekdayName(startedAt.weekday, locale: locale);
    final clock = _formatClock(startedAt, locale: locale);
    return l10n?.weekdayAt(weekday, clock) ?? '$weekday at $clock';
  }

  // Fallback: coarse day count.
  final days = age.inDays;
  return l10n?.daysAgo(days) ?? '$days days ago';
}

String _formatClock(DateTime t, {String? locale}) {
  if (locale != null) {
    return DateFormat.jm(locale).format(t);
  }
  // Manual formatting for consistent test output (no ICU locale dependency).
  final hour24 = t.hour;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '$hour12:$minute $period';
}

String _weekdayName(int weekday, {String? locale}) {
  if (locale != null) {
    // Create a DateTime for the given weekday (Mon=1 → 2024-01-01 is a Monday).
    final reference = DateTime(2024, 1, weekday);
    return DateFormat.EEEE(locale).format(reference);
  }
  const names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return names[weekday - 1];
}

/// Dialog shown on app start when a previously active workout is found in Hive.
///
/// Returns [ResumeWorkoutResult.resume] to continue the workout,
/// [ResumeWorkoutResult.discard] to delete it, or `null` if dismissed.
///
/// When the workout is older than [_staleThreshold], the dialog swaps in
/// reworded copy plus a muted line describing when the session was
/// interrupted, and renames the primary action to "Resume anyway".
class ResumeWorkoutDialog extends StatelessWidget {
  const ResumeWorkoutDialog({
    required this.workoutName,
    required this.startedAt,
    this.now,
    super.key,
  });

  final String workoutName;
  final DateTime startedAt;

  /// Injection seam for tests. When null the dialog samples [DateTime.now] at
  /// build time. Tests pass a fixed value so age-dependent assertions do not
  /// flake when the suite runs near midnight.
  final DateTime? now;

  static Future<ResumeWorkoutResult?> show(
    BuildContext context, {
    required String workoutName,
    required DateTime startedAt,
    DateTime? now,
  }) {
    return showDialog<ResumeWorkoutResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ResumeWorkoutDialog(
        workoutName: workoutName,
        startedAt: startedAt,
        now: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final effectiveNow = now ?? DateTime.now();
    final age = effectiveNow.difference(startedAt);
    final isStale = isStaleWorkout(age);

    return AlertDialog(
      title: Text(
        isStale ? l10n.resumeWorkoutStaleTitle : l10n.resumeWorkoutTitle,
      ),
      content: isStale
          ? Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '"$workoutName"', style: AppTextStyles.title),
                  const TextSpan(text: '\n'),
                  TextSpan(
                    text: l10n.workoutInterrupted(
                      formatResumeAge(startedAt, effectiveNow, l10n: l10n),
                    ),
                    style: AppTextStyles.body.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            )
          : Text(l10n.workoutInProgress(workoutName)),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(ResumeWorkoutResult.discard),
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          child: Text(l10n.discard),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(ResumeWorkoutResult.resume),
          child: Text(isStale ? l10n.resumeAnyway : l10n.resume),
        ),
      ],
    );
  }
}
