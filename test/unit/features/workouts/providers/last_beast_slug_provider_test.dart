import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/workouts/providers/last_beast_slug_provider.dart';

/// Pins the Hive-backed last-beast-slug accessor: null until a beast is
/// recorded; the recorded slug survives a fresh provider read (the 1-deep
/// no-repeat guard reads it next session).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('last_beast_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(HiveService.userPrefs);
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('null when nothing recorded', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(lastBeastSlugProvider), isNull);
  });

  test('record persists the slug across a fresh provider read', () async {
    final container = ProviderContainer();
    await container
        .read(lastBeastSlugProvider.notifier)
        .record('chest_iron_golem_1');
    expect(container.read(lastBeastSlugProvider), 'chest_iron_golem_1');
    container.dispose();

    final reopened = ProviderContainer();
    addTearDown(reopened.dispose);
    expect(reopened.read(lastBeastSlugProvider), 'chest_iron_golem_1');
  });
}
