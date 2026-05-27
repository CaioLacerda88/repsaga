import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/data/base_repository.dart';

/// Resolves localized display names for default workout templates by joining
/// against `workout_template_translations`.
///
/// Phase 32 PR 32a contract:
///   * Default templates carry a stable `template_slug` (e.g. `push_day`).
///   * `(template_slug, locale)` is the PK of `workout_template_translations`.
///   * `'en'` is the source-of-truth seed in migration 00014 — any unsupported
///     locale falls back to `'en'` rather than the verbatim DB literal.
///
/// The resolver is a thin pure-data adapter. It takes a set of `templateSlug`s
/// and a requested locale, executes one `IN`-list query, and returns a
/// `{slug -> localized name}` map. Callers (currently `RoutineRepository`)
/// apply the map at the rewrite site so the public read APIs continue to
/// return `Routine` objects with `name` populated.
///
/// User-created routines (slug == null) are NOT passed to this resolver —
/// their `name` is the user's verbatim input and never needs translation.
class WorkoutTemplateTranslationResolver extends BaseRepository {
  WorkoutTemplateTranslationResolver(this._client, {super.recoveryRecorder});

  final supabase.SupabaseClient _client;

  /// Fetch localized names for [slugs] in [locale].
  ///
  /// Returns a `{slug -> name}` map. Slugs without a `(slug, locale)` row
  /// fall back to the `(slug, 'en')` row; slugs with neither are omitted
  /// from the result (caller keeps the original `name`).
  ///
  /// Empty [slugs] short-circuits without a network call.
  Future<Map<String, String>> resolveNames({
    required Iterable<String> slugs,
    required String locale,
  }) async {
    final slugList = slugs.toSet().toList();
    if (slugList.isEmpty) return const {};

    return mapException(() async {
      // One query: pull both the requested locale AND the 'en' fallback for
      // every requested slug. We do the cascade client-side so a single
      // round-trip covers both the happy path and the missing-translation
      // fallback.
      final localesToFetch = locale == 'en' ? ['en'] : [locale, 'en'];

      final data = await _client
          .from('workout_template_translations')
          .select('template_slug, locale, name')
          .inFilter('template_slug', slugList)
          .inFilter('locale', localesToFetch);

      final rows = (data as List).cast<Map<String, dynamic>>();

      // Bucket rows by slug then locale.
      final bySlug = <String, Map<String, String>>{};
      for (final row in rows) {
        final slug = row['template_slug'] as String;
        final loc = row['locale'] as String;
        final name = row['name'] as String;
        bySlug.putIfAbsent(slug, () => <String, String>{})[loc] = name;
      }

      // Resolve cascade: requested locale → 'en'. Omit slugs without either
      // (caller falls back to `routine.name` from the templates table).
      final out = <String, String>{};
      for (final slug in slugList) {
        final byLocale = bySlug[slug];
        if (byLocale == null) continue;
        final resolved = byLocale[locale] ?? byLocale['en'];
        if (resolved != null) out[slug] = resolved;
      }
      return out;
    });
  }
}
