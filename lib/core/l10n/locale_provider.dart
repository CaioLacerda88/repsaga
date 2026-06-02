import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../features/auth/providers/auth_providers.dart';
import '../../features/profile/providers/profile_providers.dart';
import '../local_storage/cache_service.dart';
import '../local_storage/hive_service.dart';

const _hiveKey = 'locale';

/// Hive boxes that store locale-dependent data and must be evicted whenever
/// the user switches locales. Keeping cached pt content visible after a
/// switch to en (or vice-versa) would corrupt the UX, so we wipe these
/// boxes synchronously before the new locale propagates to repositories.
const _localeAffectedBoxes = <String>[
  HiveService.exerciseCache,
  HiveService.routineCache,
  HiveService.prCache,
  HiveService.workoutHistoryCache,
];

class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() {
    final box = Hive.box(HiveService.userPrefs);
    final code = box.get(_hiveKey, defaultValue: 'en') as String;
    return Locale(code);
  }

  Future<void> setLocale(Locale locale) async {
    if (locale.languageCode == state.languageCode) {
      // No-op: avoids needless cache wipes when callers re-emit the
      // current locale (e.g., reconcileWithRemote handing the same value).
      return;
    }

    final box = Hive.box(HiveService.userPrefs);
    await box.put(_hiveKey, locale.languageCode);

    // Evict locale-affected caches BEFORE flipping state and BEFORE
    // _syncToRemote so that the next provider rebuild reads from the
    // network under the new locale instead of stale cached payloads.
    await _clearLocaleAffectedCaches();

    state = locale;

    _syncToRemote(locale.languageCode);
  }

  Future<void> reconcileWithRemote(String remoteCode) async {
    final localCode = state.languageCode;
    if (remoteCode == localCode) return;

    final box = Hive.box(HiveService.userPrefs);
    await box.put(_hiveKey, remoteCode);

    // Same eviction discipline as setLocale: clear before state flip so
    // listeners that rebuild on the new locale don't read pre-switch data.
    await _clearLocaleAffectedCaches();

    state = Locale(remoteCode);
  }

  Future<void> _clearLocaleAffectedCaches() async {
    final cache = ref.read(cacheServiceProvider);
    for (final boxName in _localeAffectedBoxes) {
      await cache.clearBox(boxName);
    }
  }

  void _syncToRemote(String languageCode) {
    // Fire-and-forget with one explicit try/catch around the entire side
    // effect — including the synchronous `ref.read` lookups, since
    // currentUserIdProvider touches Supabase.instance which throws an
    // AssertionError under any test harness that hasn't booted Supabase.
    // Routing both sync and async failure paths through the same debugPrint
    // keeps the error shape consistent on physical devices (PR 32g style).
    unawaited(() async {
      try {
        final userId = ref.read(currentUserIdProvider);
        if (userId == null) return;
        final repo = ref.read(profileRepositoryProvider);
        await repo.updateLocale(userId, languageCode);
      } catch (e) {
        debugPrint('[LocaleNotifier] Failed to sync locale to remote: $e');
      }
    }());
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(
  LocaleNotifier.new,
);
