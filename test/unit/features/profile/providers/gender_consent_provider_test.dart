import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/profile/providers/gender_consent_provider.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gender_consent_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(HiveService.userPrefs);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('default value is FALSE — banner must show on first open', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(genderConsentProvider), false);
  });

  test('reads persisted true from Hive — banner suppressed', () async {
    await Hive.box(HiveService.userPrefs).put('gender_consent_enabled', true);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(genderConsentProvider), true);
  });

  test('setEnabled(true) persists across rebuilds', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(genderConsentProvider.notifier).setEnabled(true);

    expect(container.read(genderConsentProvider), true);

    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    expect(container2.read(genderConsentProvider), true);
  });

  test(
    'setEnabled(false) flips the persisted value — withdrawal parity with sibling providers',
    () async {
      // PR #309 review N3 — even though gender's documented withdrawal
      // path is clearing the value via the editor (not a Settings
      // toggle), the provider API itself must support `setEnabled(false)`
      // for parity with `bodyweightConsentProvider` /
      // `analyticsEnabledProvider`. Any future surface that adds a
      // dedicated gender-withdrawal control will need this contract.
      await Hive.box(HiveService.userPrefs).put('gender_consent_enabled', true);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(genderConsentProvider), true);

      await container.read(genderConsentProvider.notifier).setEnabled(false);

      expect(container.read(genderConsentProvider), false);
      expect(
        Hive.box(HiveService.userPrefs).get('gender_consent_enabled'),
        false,
      );
    },
  );
}
