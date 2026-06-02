import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reads an ARB file and returns only the message keys (no @-metadata keys,
/// no @@locale).
Set<String> _messageKeys(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: 'ARB file missing: $path');
  final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return map.keys.where((k) => !k.startsWith('@')).toSet();
}

/// Reads an ARB file and returns a map of message key -> value.
Map<String, String> _messageValues(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: 'ARB file missing: $path');
  final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in map.entries)
      if (!e.key.startsWith('@')) e.key: e.value as String,
  };
}

void main() {
  group('ARB completeness', () {
    late Set<String> enKeys;
    late Set<String> ptKeys;

    setUpAll(() {
      // Resolve paths relative to the project root (test runner cwd).
      enKeys = _messageKeys('lib/l10n/app_en.arb');
      ptKeys = _messageKeys('lib/l10n/app_pt.arb');
    });

    test('every key in app_en.arb exists in app_pt.arb', () {
      final missingInPt = enKeys.difference(ptKeys);
      expect(
        missingInPt,
        isEmpty,
        reason:
            'Keys in app_en.arb but missing from app_pt.arb:\n'
            '${missingInPt.join('\n')}',
      );
    });

    test('every key in app_pt.arb exists in app_en.arb', () {
      final missingInEn = ptKeys.difference(enKeys);
      expect(
        missingInEn,
        isEmpty,
        reason:
            'Keys in app_pt.arb but missing from app_en.arb:\n'
            '${missingInEn.join('\n')}',
      );
    });

    test('both files have the same number of message keys', () {
      expect(
        enKeys.length,
        equals(ptKeys.length),
        reason:
            'EN has ${enKeys.length} keys, PT has ${ptKeys.length} keys. '
            'They must match.',
      );
    });
  });

  group('ARB translation quality', () {
    late Map<String, String> enValues;
    late Map<String, String> ptValues;

    /// Keys where EN == PT is expected (brand names, abbreviations,
    /// identical short words, or format-only strings).
    const allowedIdentical = <String>{
      'appName', // RepSaga
      'prsLabel', // PRs
      'setTypeDropset', // Drop Set
      'chartMetricE1rm', // e1RM
      'ok', // OK
      'email', // E-mail (PT uses E-mail too)
      'muscleGroupCardio', // Cardio
      'weightUnitKg', // KG
      'weightUnitLbs', // LBS
      'setTypeAbbrDropset', // D
      'setTypeAbbrFailure', // F
      'or', // OU (different but short)
      // Cluster 3 — gym-vernacular loanwords. pt-BR Brazilian gym slang
      // uses "ranks" verbatim; "+5 ranks" reads natively in both locales.
      'rankUpOverflowFlipbookLabel',
      // Phase 30 PR 30a — format-only template strings. Punctuation +
      // placeholders only, no localizable prose.
      'b3PrPillTemplate', // "{exercise} · {weight}kg × {reps}"
      'b2RankCopy', // "{bodyPart} · RANK {n}"
      // Phase 31 Pass 3 — Mission Debrief rank-up arrow grammar. "Rank"
      // is the gym-vernacular loanword used identically in pt-BR + en
      // (same precedent as `rankUpOverflowFlipbookLabel`); the rest is
      // pure format (placeholders + arrow glyph). 22 chars trips the
      // placeholderOnly length floor, so allow-list it explicitly.
      'postSessionRankUpArrow', // "Rank {fromRank} → {toRank}"
      // Phase 32 PR 32f — History feed format strings. "XP" + "PR" are
      // gym-vernacular loanwords used identically in pt-BR + en
      // (same precedent as `postSessionXpLabel` /
      // `rankUpOverflowFlipbookLabel`); the rest is pure format
      // (placeholders + diamond glyph + middle dot). These exceed the
      // 20-char placeholderOnly floor, so allow-list them explicitly.
      'historyCardXpEyebrow', // "+{xp} XP"
      'historyCardPrCount', // "◆ {count} PR"
      // PR #285 — detail strip split into two spans so XP (hotViolet) and
      // PRs (heroGold via RewardAccent) can be colored independently.
      // Both spans remain pure format on the gym-vernacular loanwords.
      'historyDetailStripXpPart', // "+{xp} XP"
      'historyDetailStripPrPart', // "{prs} PRs"
    };

    /// Pattern for format-only strings (only placeholders and punctuation).
    final placeholderOnly = RegExp(
      r'^[\s{}\w,.<>=|/~\-\u00b7\u00d7\u2014:@#$%^&*()!?]*$',
    );

    setUpAll(() {
      enValues = _messageValues('lib/l10n/app_en.arb');
      ptValues = _messageValues('lib/l10n/app_pt.arb');
    });

    test('PT values differ from EN values for non-trivial keys', () {
      final untranslated = <String>[];

      for (final key in enValues.keys) {
        // Skip allowed-identical keys.
        if (allowedIdentical.contains(key)) continue;

        // Skip exercise name keys (some names like "Leg Press" are the same).
        if (key.startsWith('exerciseName_')) continue;

        final enVal = enValues[key];
        final ptVal = ptValues[key];

        if (enVal == null || ptVal == null) continue;

        // Skip format-only strings (e.g. "{count}x per week" patterns vary).
        if (placeholderOnly.hasMatch(enVal) && enVal.length < 20) continue;

        if (enVal == ptVal) {
          untranslated.add(key);
        }
      }

      expect(
        untranslated,
        isEmpty,
        reason:
            'These PT keys have the same value as EN (likely untranslated):\n'
            '${untranslated.join('\n')}',
      );
    });
  });
}
