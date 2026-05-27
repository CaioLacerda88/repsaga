/// Unit tests for [WorkoutTemplateTranslationResolver].
///
/// Phase 32 PR 32a: default routine display names move from
/// `workout_templates.name` (English literal) to a per-locale row in
/// `workout_template_translations`. The resolver is the one place the cascade
/// `requested locale → 'en' → omitted` lives — these tests pin it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/routines/data/workout_template_translation_resolver.dart';

import '../../../_helpers/fake_supabase.dart';

void main() {
  group('WorkoutTemplateTranslationResolver.resolveNames', () {
    test('returns pt name when pt row exists for requested locale', () async {
      // Resolver pulls both en + pt in one query when locale != 'en'.
      // Both rows present → pt wins.
      final client = FakeSupabaseClient(
        FakeQueryBuilder(
          data: const [
            {'template_slug': 'push_day', 'locale': 'en', 'name': 'Push Day'},
            {
              'template_slug': 'push_day',
              'locale': 'pt',
              'name': 'Dia de Empurrar',
            },
          ],
        ),
      );
      final resolver = WorkoutTemplateTranslationResolver(client);

      final names = await resolver.resolveNames(
        slugs: const ['push_day'],
        locale: 'pt',
      );

      expect(names['push_day'], 'Dia de Empurrar');
    });

    test('returns en name when locale is en (no fallback needed)', () async {
      final client = FakeSupabaseClient(
        FakeQueryBuilder(
          data: const [
            {'template_slug': 'push_day', 'locale': 'en', 'name': 'Push Day'},
          ],
        ),
      );
      final resolver = WorkoutTemplateTranslationResolver(client);

      final names = await resolver.resolveNames(
        slugs: const ['push_day'],
        locale: 'en',
      );

      expect(names['push_day'], 'Push Day');
    });

    test('falls back to en when requested locale row is missing', () async {
      // Spec: 'en' is the source-of-truth seed in migration 00014. An
      // unsupported / partially-seeded locale falls back to 'en' rather than
      // the verbatim DB literal.
      final client = FakeSupabaseClient(
        FakeQueryBuilder(
          data: const [
            {'template_slug': 'arms_abs', 'locale': 'en', 'name': 'Arms & Abs'},
            // No 'fr' row — fallback to 'en' is exercised.
          ],
        ),
      );
      final resolver = WorkoutTemplateTranslationResolver(client);

      final names = await resolver.resolveNames(
        slugs: const ['arms_abs'],
        locale: 'fr',
      );

      expect(
        names['arms_abs'],
        'Arms & Abs',
        reason: "missing 'fr' row should cascade to 'en' rather than omit",
      );
    });

    test(
      'omits slug entirely when neither requested locale nor en exists',
      () async {
        // No rows at all — slug is omitted from the returned map so the
        // caller can keep the verbatim `routine.name` from `workout_templates`.
        final client = FakeSupabaseClient(FakeQueryBuilder(data: const []));
        final resolver = WorkoutTemplateTranslationResolver(client);

        final names = await resolver.resolveNames(
          slugs: const ['ghost_template'],
          locale: 'pt',
        );

        expect(names, isEmpty);
      },
    );

    test('handles multiple slugs in a single call', () async {
      final client = FakeSupabaseClient(
        FakeQueryBuilder(
          data: const [
            {'template_slug': 'push_day', 'locale': 'en', 'name': 'Push Day'},
            {
              'template_slug': 'push_day',
              'locale': 'pt',
              'name': 'Dia de Empurrar',
            },
            {
              'template_slug': '5x5_strength',
              'locale': 'pt',
              'name': 'Força 5x5',
            },
            // No en row for 5x5_strength in this fixture — pt-only is still
            // a valid resolution.
          ],
        ),
      );
      final resolver = WorkoutTemplateTranslationResolver(client);

      final names = await resolver.resolveNames(
        slugs: const ['push_day', '5x5_strength'],
        locale: 'pt',
      );

      expect(names['push_day'], 'Dia de Empurrar');
      expect(names['5x5_strength'], 'Força 5x5');
    });

    test('short-circuits without a network call on empty slug set', () async {
      // Empty input must not issue a query — flush an error into the builder
      // and assert the call still returns successfully.
      final builder = FakeQueryBuilder(
        error: Exception('should not be called'),
      );
      final client = FakeSupabaseClient(builder);
      final resolver = WorkoutTemplateTranslationResolver(client);

      final names = await resolver.resolveNames(
        slugs: const <String>[],
        locale: 'pt',
      );

      expect(names, isEmpty);
      expect(
        builder.calledMethods,
        isEmpty,
        reason: 'empty input must short-circuit before from(...).select(...)',
      );
    });
  });
}
