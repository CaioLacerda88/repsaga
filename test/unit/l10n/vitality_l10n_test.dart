import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/l10n/app_localizations.dart';

Future<AppLocalizations> _load(Locale locale) async {
  return AppLocalizations.delegate.load(locale);
}

void main() {
  group('Vitality l10n — band labels + dormant copy', () {
    test('en: all four new keys return their canonical English copy', () async {
      final l10n = await _load(const Locale('en'));
      expect(l10n.vitalityStateBandActive, equals('Active'));
      expect(l10n.vitalityStateBandWaning, equals('Waning'));
      expect(l10n.vitalityStateBandDormant, equals('Dormant'));
      expect(l10n.withinRankXpSuffix, equals('to next rank'));
    });

    test(
      'pt: all four new keys return their canonical Portuguese copy',
      () async {
        final l10n = await _load(const Locale('pt'));
        expect(l10n.vitalityStateBandActive, equals('Ativo'));
        expect(l10n.vitalityStateBandWaning, equals('Esmorecendo'));
        expect(l10n.vitalityStateBandDormant, equals('Dormente'));
        expect(l10n.withinRankXpSuffix, equals('para o próximo rank'));
      },
    );

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
