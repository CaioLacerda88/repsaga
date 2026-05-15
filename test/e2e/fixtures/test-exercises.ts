/**
 * Known exercise names from supabase/seed.sql and exercise_translations.
 *
 * Use these constants in tests instead of raw strings to avoid typos and
 * make it obvious when a name change in seed data would break tests.
 *
 * Verified against supabase/seed.sql — exact names as stored in the database.
 *
 * SEED_EXERCISES provides English names for the exercises used across all tests.
 *
 * EXERCISE_NAMES provides locale-keyed names for exercises used in
 * locale-aware tests. Values are pulled from:
 *   - en: supabase/migrations/00032_backfill_exercise_translations_en.sql
 *         (mirroring the original exercises.name column)
 *   - pt: supabase/migrations/00033_seed_exercise_translations_pt.sql
 *         (byte-for-byte match to the name values in that migration)
 */

export const SEED_EXERCISES = {
  benchPress: 'Barbell Bench Press',
  squat: 'Barbell Squat',
  deadlift: 'Deadlift',
  overheadPress: 'Overhead Press',
  // Phase 24c-8 — bodyweight prompt E2E uses Pull-Up because it's one of
  // the 20 curated `uses_bodyweight_load = TRUE` exercises (per
  // `00056_add_bodyweight_load_semantics.sql`). Picking pull-up keeps
  // the test surface aligned with what real users will most commonly
  // hit the prompt on (the move is in nearly every routine library).
  pullUp: 'Pull-Up',
} as const;

/**
 * Locale-keyed exercise name map.
 *
 * Keys are exercise slugs (from exercises.slug column after Phase 15f).
 * Values are objects with `en` and `pt` string fields.
 *
 * When writing locale-sensitive selectors or assertions:
 *   EXERCISE_NAMES.barbell_bench_press[user.locale]
 *   // 'Barbell Bench Press' (en) or 'Supino Reto com Barra' (pt)
 *
 * pt values MUST match the `name` column in 00033_seed_exercise_translations_pt.sql
 * byte-for-byte. Do not translate or paraphrase.
 */
export const EXERCISE_NAMES: Record<string, { en: string; pt: string }> = {
  // CHEST
  barbell_bench_press: {
    en: 'Barbell Bench Press',
    pt: 'Supino Reto com Barra',
  },
  incline_barbell_bench_press: {
    en: 'Incline Barbell Bench Press',
    pt: 'Supino Inclinado com Barra',
  },
  decline_barbell_bench_press: {
    en: 'Decline Barbell Bench Press',
    pt: 'Supino Declinado com Barra',
  },
  dumbbell_bench_press: {
    en: 'Dumbbell Bench Press',
    pt: 'Supino Reto com Halteres',
  },
  incline_dumbbell_press: {
    en: 'Incline Dumbbell Press',
    pt: 'Supino Inclinado com Halteres',
  },
  push_up: {
    en: 'Push-Up',
    pt: 'Flexão de Braços',
  },
  // BACK
  barbell_bent_over_row: {
    en: 'Barbell Bent-Over Row',
    pt: 'Remada Curvada com Barra',
  },
  deadlift: {
    en: 'Deadlift',
    pt: 'Levantamento Terra',
  },
  pull_up: {
    en: 'Pull-Up',
    pt: 'Barra Fixa',
  },
  lat_pulldown: {
    en: 'Lat Pulldown',
    pt: 'Puxada na Polia Alta',
  },
  // LEGS
  barbell_squat: {
    en: 'Barbell Squat',
    pt: 'Agachamento com Barra',
  },
  romanian_deadlift: {
    en: 'Romanian Deadlift',
    pt: 'Levantamento Terra Romeno',
  },
  leg_press: {
    en: 'Leg Press',
    pt: 'Leg Press',
  },
  // SHOULDERS
  overhead_press: {
    en: 'Overhead Press',
    pt: 'Desenvolvimento com Barra',
  },
  lateral_raise: {
    en: 'Lateral Raise',
    pt: 'Elevação Lateral',
  },
  // ARMS
  barbell_curl: {
    en: 'Barbell Curl',
    pt: 'Rosca Direta com Barra',
  },
  dumbbell_curl: {
    en: 'Dumbbell Curl',
    pt: 'Rosca com Halteres',
  },
  tricep_pushdown: {
    en: 'Tricep Pushdown',
    pt: 'Tríceps Pulley',
  },
  // CORE
  plank: {
    en: 'Plank',
    pt: 'Prancha',
  },
  crunches: {
    en: 'Crunches',
    pt: 'Abdominal',
  },
} as const;

/**
 * Helper: return the exercise name for the given slug and locale.
 * Falls back to English if the locale is not in the map.
 */
export function exerciseName(
  slug: keyof typeof EXERCISE_NAMES,
  locale: 'en' | 'pt',
): string {
  return EXERCISE_NAMES[slug]?.[locale] ?? EXERCISE_NAMES[slug]?.en ?? slug;
}
