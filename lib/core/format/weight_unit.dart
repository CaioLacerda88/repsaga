/// Weight-unit conversion helpers.
///
/// All weight values are persisted server-side in **kilograms** regardless of
/// the user's preferred display unit (`profiles.weight_unit` ∈ {`kg`, `lbs`}).
/// The UI layer is responsible for converting on render and on save so the
/// backend math (XP, PR detection, RPCs) operates on a single canonical unit.
///
/// Lives in `core/format/` rather than a feature folder because the
/// conversions are cross-cutting: profile UI, exercise PR cards, and the
/// progress chart all consume the same constant. Keeping it at `core/`
/// avoids `features/X` importing `features/Y` and centralises the rounding
/// constant so a future precision adjustment touches one file.
library;

/// Conversion factor: pounds per kilogram. 1 kg ≈ 2.20462 lb.
const double kgPerLb = 2.20462;

/// Convert kilograms to pounds.
double kgToLb(double kg) => kg * kgPerLb;

/// Convert pounds to kilograms.
double lbToKg(double lb) => lb / kgPerLb;

/// Server-side bodyweight bounds (kg) — mirrors the `valid_profiles_bodyweight_kg`
/// CHECK constraint in migration `00056_add_bodyweight_load_semantics.sql`.
/// Editing UI uses these to validate before round-tripping to Supabase so the
/// user gets a friendly inline error instead of a 23514 failure surfaced as a
/// generic snackbar.
const double bodyweightMinKg = 25;
const double bodyweightMaxKg = 250;

/// Display-equivalent bounds for the lbs unit. Derived from the kg bounds via
/// the same `kgPerLb` constant so the UI never drifts from the SQL CHECK. The
/// sheet rounds these to whole numbers for display ("55–550 lbs" reads
/// cleaner than "55.12–551.16") — the actual validation still re-converts to
/// kg and compares against [bodyweightMinKg] / [bodyweightMaxKg] so a user
/// who types `54` or `551` lbs is rejected by the same boundary the server
/// would reject.
double get bodyweightMinLb => kgToLb(bodyweightMinKg);
double get bodyweightMaxLb => kgToLb(bodyweightMaxKg);

/// True when [kg] satisfies the server CHECK constraint.
bool isBodyweightInRange(double kg) =>
    kg >= bodyweightMinKg && kg <= bodyweightMaxKg;
