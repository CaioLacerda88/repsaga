import 'package:intl/intl.dart';

/// Shared weekday formatter used by every surface that renders a workout's
/// completion day (Home's `BucketChipRow`, the Week Plan editor's
/// `BucketRoutineRow`).
///
/// **Why a single source of truth.**
/// Supabase stores `workouts.finished_at` (and the `completed_at` mirror in
/// `weekly_plans.routines`) as UTC. A workout finished at 23:00 BRT (UTC-3)
/// serializes to next-day 02:00Z; rendering the UTC instant directly drifts
/// the weekday label by one day relative to what the user perceives.
///
/// Two consumers diverged on the `.toLocal()` step (audit 2026-05-27):
/// `bucket_chip_row.dart` called it; `week_plan_screen.dart` did not. Same
/// `completedAt`, different weekday — Home showed "TER" while the Week
/// Plan editor showed "QUA" for a single workout. Extracting the formatter
/// here means the call sites can't drift independently; future surfaces
/// adopt the same contract by importing it.
class WeekdayFormatter {
  WeekdayFormatter._();

  /// 3-letter localized weekday label, title-cased.
  ///
  ///   - en: "Mon", "Tue", … "Sun"
  ///   - pt: "Seg", "Ter", … "Dom"   (trailing dot from intl trimmed)
  ///
  /// `date` is assumed UTC (Supabase contract); `.toLocal()` converts to
  /// the device's local zone BEFORE `DateFormat.E` extracts the weekday.
  /// Skipping the conversion is the cluster `weekday-utc-vs-local-drift`
  /// trap — same `DateTime`, different label depending on whether the
  /// caller remembered to convert.
  ///
  /// `locale` is an intl locale tag (`en`, `pt`, `pt_BR`, …). Matches the
  /// active `AppLocalizations.localeName` at call sites.
  ///
  /// `uppercase` chooses between the two house styles:
  ///   - Home chips ("TER") use `uppercase: true`.
  ///   - Week Plan row meta ("Ter") uses `uppercase: false` (title-case).
  static String shortDayLabel(
    DateTime date,
    String locale, {
    required bool uppercase,
  }) {
    final local = date.toLocal();
    final raw = DateFormat.E(locale).format(local);
    final trimmed = raw.endsWith('.') ? raw.substring(0, raw.length - 1) : raw;
    // intl should never return an empty short-weekday for a supported locale.
    // Surface unexpected stripping early in tests rather than silently
    // rendering a blank chip label in production.
    assert(
      trimmed.isNotEmpty,
      'WeekdayFormatter: intl returned empty short weekday for locale "$locale"',
    );
    if (trimmed.isEmpty) return trimmed;
    if (uppercase) return trimmed.toUpperCase();
    return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
  }
}
