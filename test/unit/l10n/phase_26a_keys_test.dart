import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/l10n/app_localizations.dart';

Future<AppLocalizations> _load(Locale locale) async {
  return AppLocalizations.delegate.load(locale);
}

void main() {
  group('Phase 26a — new l10n keys', () {
    test('en: all four new keys return non-empty strings', () async {
      final l10n = await _load(const Locale('en'));
      expect(l10n.vitalityStateBandActive, isNotEmpty);
      expect(l10n.vitalityStateBandWaning, isNotEmpty);
      expect(l10n.vitalityStateBandDormant, isNotEmpty);
      expect(l10n.withinRankXpSuffix, isNotEmpty);
    });

    test('pt: all four new keys return non-empty strings', () async {
      final l10n = await _load(const Locale('pt'));
      expect(l10n.vitalityStateBandActive, 'Ativo');
      expect(l10n.vitalityStateBandWaning, 'Esmorecendo');
      expect(l10n.vitalityStateBandDormant, 'Dormente');
      expect(l10n.withinRankXpSuffix, 'para o próximo rank');
    });

    test(
      'en: vitalityCopyDormant has been rewritten (no longer Untested copy)',
      () async {
        final l10n = await _load(const Locale('en'));
        expect(l10n.vitalityCopyDormant, isNot(contains('first stride')));
        expect(l10n.vitalityCopyDormant.toLowerCase(), contains('dormant'));
      },
    );

    test('pt: vitalityCopyDormant has been rewritten', () async {
      final l10n = await _load(const Locale('pt'));
      expect(l10n.vitalityCopyDormant, isNot(contains('primeiro passo')));
      expect(l10n.vitalityCopyDormant.toLowerCase(), contains('dormente'));
    });
  });
}
