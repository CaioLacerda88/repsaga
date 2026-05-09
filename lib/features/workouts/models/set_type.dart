enum SetType {
  working,
  warmup,
  dropset,
  failure;

  String get displayName => switch (this) {
    working => 'Working',
    warmup => 'Warm-up',
    dropset => 'Drop Set',
    failure => 'To Failure',
  };

  /// Hard-coded English shorthand. **Deprecated for UI use** — Family 6
  /// (PR fix/workouts-a11y-i18n-combined) replaced the only production
  /// caller (`set_row.dart` _SetNumberCell) with a localized lookup against
  /// the existing `setTypeAbbr*` ARB keys. The visible micro-label now
  /// honors the user's locale (en: W/WU/D/F, pt: N/AQ/D/F) and matches the
  /// convention already used by `workout_detail_screen.dart`.
  ///
  /// Kept in the model for any future test-only / debug-only use case
  /// where a locale-stable English string is genuinely useful (e.g.
  /// log lines, analytics breadcrumbs). Do NOT call this from production
  /// UI — use `_localizedSetTypeAbbr(setType, l10n)` (or the equivalent
  /// switch over `setTypeAbbr*` keys) instead.
  @Deprecated(
    'UI must localize via setTypeAbbr* ARB keys; see set_row.dart '
    '_localizedSetTypeAbbr. Kept only for non-UI English-stable callers.',
  )
  String get tinyAbbr => switch (this) {
    working => 'WK',
    warmup => 'WU',
    dropset => 'DR',
    failure => 'FL',
  };

  static SetType fromString(String value) =>
      values.firstWhere((e) => e.name == value);
}
