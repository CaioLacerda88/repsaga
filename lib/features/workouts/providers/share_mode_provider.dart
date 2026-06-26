import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/local_storage/hive_service.dart';
import '../domain/share_mode.dart';

/// Hive key (in [HiveService.userPrefs]) where the user's preferred default
/// share mode is persisted.
///
/// Stored as the enum's [ShareMode.name] string (`'bestiary'` / `'cleanFlex'`)
/// rather than the ordinal so a future re-ordering or insertion of a mode
/// can't silently re-map a persisted preference. Lives in `userPrefs`, which
/// is excluded from [HiveService.cacheSchemaBoxes] — the preference survives
/// every cache schema bump (it's durable user state, not a read-through
/// cache).
const String _shareModeDefaultKey = 'share_mode_default';

/// Sync-readable preference for "which share mode does this user prefer by
/// default?" Backed by [HiveService.userPrefs] so the read is O(1) and
/// available before the first frame paints.
///
/// Mirrors [AgePromptDismissalNotifier]: the `userPrefs` box is opened during
/// `HiveService.init()` (which runs before `runApp`), so reading
/// `Hive.box(HiveService.userPrefs)` from [build] is race-free. A sync
/// [Notifier] (not [AsyncNotifier]) keeps the share-sheet / preview call
/// sites + widget tests trivial.
///
/// **Default = [ShareMode.bestiary]** (spec §7: Bestiary is the default,
/// playful mode for most users). A missing/unrecognised persisted value
/// floors to bestiary.
class ShareModeDefaultNotifier extends Notifier<ShareMode> {
  @override
  ShareMode build() {
    final box = Hive.box<dynamic>(HiveService.userPrefs);
    final stored = box.get(_shareModeDefaultKey) as String?;
    return _fromName(stored);
  }

  /// Persist [mode] as the user's default. Idempotent — re-persisting the
  /// same mode no-ops the state emit (Riverpod only notifies on a value
  /// change), so the share-sheet's `ref.listen` callbacks stay quiet on a
  /// no-op set.
  Future<void> setDefault(ShareMode mode) async {
    if (state == mode) return;
    final box = Hive.box<dynamic>(HiveService.userPrefs);
    await box.put(_shareModeDefaultKey, mode.name);
    state = mode;
  }

  static ShareMode _fromName(String? name) {
    for (final m in ShareMode.values) {
      if (m.name == name) return m;
    }
    return ShareMode.bestiary;
  }
}

final shareModeDefaultProvider =
    NotifierProvider<ShareModeDefaultNotifier, ShareMode>(
      ShareModeDefaultNotifier.new,
    );
