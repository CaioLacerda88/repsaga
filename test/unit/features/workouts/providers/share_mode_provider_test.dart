import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/workouts/domain/share_mode.dart';
import 'package:repsaga/features/workouts/providers/share_mode_provider.dart';

/// Pins the Hive-backed share-mode default preference: bestiary is the
/// default when nothing is persisted; setting a default persists across a
/// fresh provider read (the next session opens in the chosen mode).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('share_mode_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(HiveService.userPrefs);
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('default is bestiary when nothing is persisted', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(shareModeDefaultProvider), ShareMode.bestiary);
  });

  test('setDefault persists across a fresh provider read', () async {
    final container = ProviderContainer();

    await container
        .read(shareModeDefaultProvider.notifier)
        .setDefault(ShareMode.cleanFlex);
    expect(container.read(shareModeDefaultProvider), ShareMode.cleanFlex);
    container.dispose();

    // A brand-new container re-reads the persisted preference from Hive.
    final reopened = ProviderContainer();
    addTearDown(reopened.dispose);
    expect(reopened.read(shareModeDefaultProvider), ShareMode.cleanFlex);
  });
}
