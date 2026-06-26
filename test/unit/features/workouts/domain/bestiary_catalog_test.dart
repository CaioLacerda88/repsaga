import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/domain/beast_card.dart';
import 'package:repsaga/features/workouts/domain/bestiary_catalog.dart';

/// Parity + integrity tests for the shipped bestiary content. This REPLACES
/// the en/pt parity tooling the ARB convention would have given for free —
/// the bestiary ships bulk content as inline `name{en,pt}` JSON, so a unit
/// test is the gate that every entry carries both locales (see docs/WIP.md
/// boundary inventory).
BestiaryCatalog loadRealCatalog() {
  String read(String name) => File('assets/bestiary/$name').readAsStringSync();
  return BestiaryCatalog.parse(
    baseRaw: read('bestiary.json'),
    epithetsRaw: read('epithets.json'),
    chimerasRaw: read('chimeras.json'),
    legendariesRaw: read('legendaries.json'),
    phrasesRaw: read('achievement_phrases.json'),
  );
}

void main() {
  final catalog = loadRealCatalog();

  void expectBothLocales(String enText, String ptText, String context) {
    expect(enText.trim(), isNotEmpty, reason: 'en empty for $context');
    expect(ptText.trim(), isNotEmpty, reason: 'pt empty for $context');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // en + pt parity (the ARB-parity replacement)
  // ───────────────────────────────────────────────────────────────────────────

  group('en+pt parity', () {
    test('every base creature has non-empty en + pt', () {
      for (final c in catalog.baseCreatures) {
        expectBothLocales(c.name.en, c.name.pt, 'base ${c.slug}');
      }
    });

    test('every epithet has non-empty en + pt', () {
      for (final e in catalog.epithets) {
        expectBothLocales(e.name.en, e.name.pt, 'epithet ${e.slug}');
      }
    });

    test(
      'every chimera (curated, by-count, lexicon) has non-empty en + pt',
      () {
        for (final list in catalog.curatedChimeras.values) {
          for (final c in list) {
            expectBothLocales(c.name.en, c.name.pt, 'curated ${c.slug}');
          }
        }
        for (final list in catalog.chimerasByCount.values) {
          for (final c in list) {
            expectBothLocales(c.name.en, c.name.pt, 'byCount ${c.slug}');
          }
        }
        for (final lex in catalog.lexicon) {
          expectBothLocales(
            lex.noun.en,
            lex.noun.pt,
            'lexicon noun ${lex.line.dbValue}',
          );
          for (final adj in lex.adjectives) {
            expectBothLocales(
              adj.en,
              adj.pt,
              'lexicon adj ${lex.line.dbValue}',
            );
          }
        }
      },
    );

    test('every legendary has non-empty en + pt', () {
      for (final l in catalog.legendaries) {
        expectBothLocales(l.name.en, l.name.pt, 'legendary ${l.slug}');
      }
    });

    test('every achievement phrase has non-empty en + pt', () {
      for (final p in catalog.phrases) {
        expectBothLocales(p.name.en, p.name.pt, 'phrase ${p.trait}');
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Counts + structural completeness
  // ───────────────────────────────────────────────────────────────────────────

  group('counts', () {
    test('84 base creatures = 7 lines x 6 tiers x 2 variants', () {
      expect(catalog.baseCreatures.length, 84);
    });

    test('every (line, tier) pair has exactly 2 variants (0 and 1)', () {
      for (final line in BodyPart.values) {
        for (final tier in BeastTier.values) {
          final variants =
              catalog.baseCreatures
                  .where((c) => c.line == line && c.tier == tier)
                  .map((c) => c.variant)
                  .toList()
                ..sort();
          expect(
            variants,
            [0, 1],
            reason: 'line ${line.dbValue} tier ${tier.label} missing a variant',
          );
        }
      }
    });

    test('all base slugs are unique', () {
      final slugs = catalog.baseCreatures.map((c) => c.slug).toList();
      expect(slugs.toSet().length, slugs.length);
    });

    test('lexicon covers all 7 lines, each with exactly 2 adjectives', () {
      expect(catalog.lexicon.length, 7);
      final lines = catalog.lexicon.map((e) => e.line).toSet();
      expect(lines.length, 7);
      for (final lex in catalog.lexicon) {
        expect(lex.adjectives.length, 2);
      }
    });

    test('legendaries cover the Slice-1 session-count milestones', () {
      final counts = catalog.legendaries.map((l) => l.sessionCount).toSet();
      expect(counts, containsAll([50, 100, 250]));
    });

    test('every phrase trait/line is parseable (no nulls leaked)', () {
      for (final p in catalog.phrases) {
        if (p.trait == 'line') {
          expect(p.line, isNotNull, reason: 'line phrase missing line key');
        }
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Structural resolve-time guards
  //
  // The resolver does a number of `firstWhere`-WITHOUT-`orElse` lookups
  // (`_lexiconFor`, `_lineFallbackPhrase`, `_phraseByTrait`) and a curated-pair
  // map lookup keyed on a `lineA+lineB` sorted token. If the SHIPPED content
  // ever drifts so one of those keys can't be found, the resolver throws a
  // `StateError`/`Bad state: No element` at RESOLVE TIME — i.e. live, on a
  // user's finished workout, with no fallback. These tests move every such
  // failure to CI: they assert the exact structural shape the resolver looks
  // up. (QA coverage hole 1b.)
  // ───────────────────────────────────────────────────────────────────────────

  group('structural resolve-time guards', () {
    test(
      'every curated-pair key is a valid, canonically-sorted BodyPart pair',
      () {
        expect(
          catalog.curatedChimeras,
          isNotEmpty,
          reason: 'curated chimera map must not be empty',
        );
        for (final key in catalog.curatedChimeras.keys) {
          final parts = key.split('+');
          expect(
            parts.length,
            2,
            reason: 'curated key "$key" must be exactly two +-joined tokens',
          );
          // Both tokens must parse to a real BodyPart (the resolver builds the
          // lookup key from `BodyPart.dbValue`s — an unparseable token would
          // never be hit but signals catalog rot).
          final a = BodyPart.tryFromDbValue(parts[0]);
          final b = BodyPart.tryFromDbValue(parts[1]);
          expect(
            a,
            isNotNull,
            reason: 'curated key "$key" part 0 not a BodyPart',
          );
          expect(
            b,
            isNotNull,
            reason: 'curated key "$key" part 1 not a BodyPart',
          );
          // The resolver's `_pairKey` sorts the two dbValues alphabetically
          // before joining. A curated key authored out of order would never
          // match the resolver's lookup → silent generative fallback (or, for
          // the named path, a miss). Assert the canonical sorted form.
          final canonical = ([parts[0], parts[1]]..sort()).join('+');
          expect(
            key,
            canonical,
            reason:
                'curated key "$key" is not in the canonical sorted form '
                '"$canonical" the resolver looks up (_pairKey sorts dbValues)',
          );
        }
      },
    );

    test('every curated pair has at least one variant', () {
      for (final entry in catalog.curatedChimeras.entries) {
        expect(
          entry.value,
          isNotEmpty,
          reason: 'curated pair "${entry.key}" has no variants to pick from',
        );
      }
    });

    test(
      'every BodyPart has a line-fallback phrase (resolver firstWhere has no orElse)',
      () {
        // `BestiaryResolver._lineFallbackPhrase` does
        //   phrases.firstWhere((p) => p.trait == 'line' && p.line == line)
        // with NO orElse — a missing line throws at resolve time for any
        // session dominated by that part. Every BodyPart must be covered.
        for (final line in BodyPart.values) {
          final match = catalog.phrases.where(
            (p) => p.trait == 'line' && p.line == line,
          );
          expect(
            match,
            isNotEmpty,
            reason:
                'no "line" fallback phrase for ${line.dbValue} — resolver '
                '_lineFallbackPhrase would throw on a ${line.dbValue}-dominant '
                'session',
          );
        }
      },
    );

    test('every BodyPart has a generative-chimera lexicon entry', () {
      // `BestiaryResolver._lexiconFor` does
      //   lexicon.firstWhere((e) => e.line == line)
      // with NO orElse. A non-curated 3-part session falls back to the
      // generative name built from the dominant + secondary lexicon entries;
      // a missing line throws at resolve time.
      for (final line in BodyPart.values) {
        final match = catalog.lexicon.where((e) => e.line == line);
        expect(
          match,
          isNotEmpty,
          reason:
              'no fusion-lexicon entry for ${line.dbValue} — resolver '
              '_lexiconFor would throw on a generative chimera fusing it',
        );
      }
    });

    test('lexicon covers all 7 lines (generative fallback completeness)', () {
      final lines = catalog.lexicon.map((e) => e.line).toSet();
      expect(lines.length, BodyPart.values.length);
      expect(lines, containsAll(BodyPart.values));
    });

    test(
      'every resolver-selectable trait phrase is present (pr, sRank, chimera)',
      () {
        // `_phraseByTrait` (firstWhere, no orElse) is called with these exact
        // trait keys in Slice 1. A missing trait throws at resolve time.
        for (final trait in const ['pr', 'sRank', 'chimera']) {
          final match = catalog.phrases.where((p) => p.trait == trait);
          expect(
            match,
            isNotEmpty,
            reason:
                'no "$trait" phrase — resolver _phraseByTrait would throw when '
                'that trait wins',
          );
        }
      },
    );
  });
}
