/// The six v1 strength tracks plus the v2 cardio track.
///
/// `dbValue` is the canonical token used in `body_part_progress.body_part`,
/// `xp_attribution` JSON keys, and `xp_events.attribution` payloads. Keep
/// these byte-for-byte aligned with PostgreSQL — any drift between Dart and
/// SQL means a backfill replay produces different rows than a live save.
///
/// `cardio` is in the enum so the schema, repositories, and UI plumbing all
/// accept it day one. As of Phase 38e it is a fully active progression track:
/// [activeBodyParts] includes it (it contributes to Character Level) while
/// [strengthBodyParts] keeps the six-track strength-only set for the class
/// resolver / Ascendant spread (cardio earns recognition via cardio titles,
/// not a class).
enum BodyPart {
  chest,
  back,
  legs,
  shoulders,
  arms,
  core,
  cardio;

  /// Token persisted in SQL and JSON. Lower-snake to match the spec §11.1
  /// CHECK contract (`body_part TEXT` literal values).
  String get dbValue => name;

  /// Reverse lookup. Returns null on unknown tokens so callers can decide
  /// whether to fail loudly (repositories) or fall back gracefully (UI
  /// reading legacy JSON).
  static BodyPart? tryFromDbValue(String value) {
    for (final bp in BodyPart.values) {
      if (bp.dbValue == value) return bp;
    }
    return null;
  }

  /// Throwing variant for repositories — a token we don't recognize is a
  /// data-integrity bug, not a UI fallback case.
  static BodyPart fromDbValue(String value) {
    final bp = tryFromDbValue(value);
    if (bp == null) {
      throw ArgumentError.value(value, 'body_part', 'unknown token');
    }
    return bp;
  }
}

/// The body parts that contribute to Character Level (Phase 38e: the six
/// strength tracks PLUS cardio — seven active tracks). The denominator in
/// `characterLevel(...)` stays 4; only the per-part rank SUM grows, so a
/// pure-strength user's level never regresses (cardio at rank 1 contributes
/// `rank - 1 = 0` to the numerator). `cardio` is appended LAST so the six
/// strength tracks keep their original order across every consumer that
/// iterates this list (the Saga rail, the provider projection, etc.).
const List<BodyPart> activeBodyParts = [
  BodyPart.chest,
  BodyPart.back,
  BodyPart.legs,
  BodyPart.shoulders,
  BodyPart.arms,
  BodyPart.core,
  BodyPart.cardio,
];

/// The six strength tracks ONLY — the input set for class resolution
/// ([ClassResolver] / Ascendant spread). Cardio lives in [activeBodyParts]
/// (it counts toward Character Level) but is deliberately EXCLUDED from the
/// class system: cardio recognition ships as cardio titles, not a class, so
/// a cardio-dominant distribution must never resolve to or perturb the
/// strength class / Ascendant balance check. Keep this list in strength
/// order; do not add cardio.
const List<BodyPart> strengthBodyParts = [
  BodyPart.chest,
  BodyPart.back,
  BodyPart.legs,
  BodyPart.shoulders,
  BodyPart.arms,
  BodyPart.core,
];
