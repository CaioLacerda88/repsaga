import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/analytics/data/analytics_repository.dart';
import 'package:repsaga/features/profile/providers/analytics_enabled_provider.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('analytics_enabled_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(HiveService.userPrefs);
    AnalyticsRepository.debugResetEnabled();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('default value is true when Hive has no entry', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(analyticsEnabledProvider), true);
  });

  test('reads persisted false from Hive', () async {
    await Hive.box(HiveService.userPrefs).put('analytics_enabled', false);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(analyticsEnabledProvider), false);
  });

  test('setting to false persists and updates AnalyticsRepository', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(analyticsEnabledProvider.notifier).setEnabled(false);

    expect(container.read(analyticsEnabledProvider), false);
    expect(Hive.box(HiveService.userPrefs).get('analytics_enabled'), false);
    expect(AnalyticsRepository.isEnabled, false);
  });

  test('setting to true persists and updates AnalyticsRepository', () async {
    await Hive.box(HiveService.userPrefs).put('analytics_enabled', false);
    AnalyticsRepository.setEnabled(false);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(analyticsEnabledProvider.notifier).setEnabled(true);

    expect(container.read(analyticsEnabledProvider), true);
    expect(AnalyticsRepository.isEnabled, true);
  });

  test(
    'build() syncs AnalyticsRepository.isEnabled with the persisted Hive value',
    () async {
      // Mirror of CrashReportsEnabledNotifier's build()-sync regression test.
      // A persisted opt-out (false) must propagate to the static
      // AnalyticsRepository gate on every rebuild, even when the static
      // flag was left enabled by a prior test or hot reload.

      await Hive.box(HiveService.userPrefs).put('analytics_enabled', false);
      // Pre-condition: static flag starts at the production default (true).
      expect(AnalyticsRepository.isEnabled, true);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(analyticsEnabledProvider), false);
      expect(
        AnalyticsRepository.isEnabled,
        false,
        reason: 'build() must sync the static flag with the Hive value',
      );

      // Flip Hive to true, invalidate, rebuild -> static flag flips back.
      await Hive.box(HiveService.userPrefs).put('analytics_enabled', true);
      container.invalidate(analyticsEnabledProvider);
      expect(container.read(analyticsEnabledProvider), true);
      expect(AnalyticsRepository.isEnabled, true);
    },
  );
}
