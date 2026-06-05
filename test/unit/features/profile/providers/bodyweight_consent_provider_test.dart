import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/profile/providers/bodyweight_consent_provider.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bodyweight_consent_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(HiveService.userPrefs);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'default value is FALSE when Hive has no entry (sensitive data — explicit opt-in)',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // LGPD Art. 11 / GDPR Art. 9: sensitive health data requires
      // explicit opt-in. The default cannot silently flip to true.
      expect(container.read(bodyweightConsentProvider), false);
    },
  );

  test('reads persisted true from Hive', () async {
    await Hive.box(
      HiveService.userPrefs,
    ).put('bodyweight_consent_enabled', true);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(bodyweightConsentProvider), true);
  });

  test('setEnabled(true) persists across rebuilds', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(bodyweightConsentProvider.notifier).setEnabled(true);

    expect(container.read(bodyweightConsentProvider), true);
    expect(
      Hive.box(HiveService.userPrefs).get('bodyweight_consent_enabled'),
      true,
    );

    // New container should observe the same persisted value.
    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    expect(container2.read(bodyweightConsentProvider), true);
  });

  test('setEnabled(false) — withdrawal flips the persisted value', () async {
    await Hive.box(
      HiveService.userPrefs,
    ).put('bodyweight_consent_enabled', true);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(bodyweightConsentProvider), true);

    await container.read(bodyweightConsentProvider.notifier).setEnabled(false);

    expect(container.read(bodyweightConsentProvider), false);
    expect(
      Hive.box(HiveService.userPrefs).get('bodyweight_consent_enabled'),
      false,
    );
  });
}
