import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/data/title_thresholds_table.dart';
import 'package:repsaga/features/rpg/data/titles_repository.dart';
import 'package:repsaga/features/rpg/models/title.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('should match the body-part catalog row-for-row', () async {
    final repo = TitlesRepository.forAssetBundleOnly();
    final catalog = await repo.loadCatalog();
    final catalogBodyParts = catalog.whereType<BodyPartTitle>().toList();
    final tableBodyParts = TitleThresholdsTable.all
        .where((e) => e.kind == TitleThresholdKind.bodyPart)
        .toList();
    expect(
      tableBodyParts.length,
      catalogBodyParts.length,
      reason: 'body-part threshold table size must match catalog',
    );
    for (final cat in catalogBodyParts) {
      final entry = tableBodyParts.firstWhere(
        (e) => e.slug == cat.slug,
        orElse: () => throw StateError('table missing slug ${cat.slug}'),
      );
      expect(entry.threshold, cat.rankThreshold);
      expect(entry.bodyPart, cat.bodyPart);
    }
  });

  test('should match the character-level catalog row-for-row', () async {
    final repo = TitlesRepository.forAssetBundleOnly();
    final catalog = await repo.loadCatalog();
    final catalogChar = catalog.whereType<CharacterLevelTitle>().toList();
    final tableChar = TitleThresholdsTable.all
        .where((e) => e.kind == TitleThresholdKind.characterLevel)
        .toList();
    expect(tableChar.length, catalogChar.length);
    for (final cat in catalogChar) {
      final entry = tableChar.firstWhere(
        (e) => e.slug == cat.slug,
        orElse: () => throw StateError('table missing slug ${cat.slug}'),
      );
      expect(entry.threshold, cat.levelThreshold);
    }
  });

  test('should match the cross-build catalog slug list', () async {
    final repo = TitlesRepository.forAssetBundleOnly();
    final catalog = await repo.loadCatalog();
    final catalogCB = catalog
        .whereType<CrossBuildTitle>()
        .map((t) => t.slug)
        .toSet();
    final tableCB = TitleThresholdsTable.all
        .where((e) => e.kind == TitleThresholdKind.crossBuild)
        .map((e) => e.slug)
        .toSet();
    expect(tableCB, catalogCB);
  });
}
