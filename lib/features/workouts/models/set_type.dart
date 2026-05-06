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

  /// Two-character gym shorthand rendered as a persistent micro-label below
  /// the set number on the active workout row (Phase 20 polish #3, post-merge).
  ///
  /// **Why this lives on the enum** rather than in the widget: the shorthand
  /// is universal across locales — every Brazilian / English / Spanish lifter
  /// reads `WU` as warm-up regardless of UI language, and tying it to the
  /// enum keeps the widget free of switch statements and prevents drift if
  /// new types are added in the future.
  ///
  /// **Why not localize**: gym shorthand is a vocabulary the app teaches via
  /// the long-press cycle. Translating `DR` to `RP` (redução de carga) would
  /// undo that teaching every time a Brazilian user reads English fitness
  /// content. Single source of vocabulary.
  String get tinyAbbr => switch (this) {
    working => 'WK',
    warmup => 'WU',
    dropset => 'DR',
    failure => 'FL',
  };

  static SetType fromString(String value) =>
      values.firstWhere((e) => e.name == value);
}
