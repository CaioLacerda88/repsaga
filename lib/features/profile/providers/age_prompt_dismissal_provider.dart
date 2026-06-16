import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/local_storage/hive_service.dart';

/// Hive key (in [HiveService.userPrefs]) where the age-prompt dismissal
/// timestamp lives.
///
/// Stored as an ISO8601 UTC string. We persist a timestamp rather than a
/// bare bool so a future "re-prompt on a major version bump" policy can read
/// the dismissal age without a schema migration. Today only presence
/// matters: any non-null value means dismissed forever.
///
/// Lives in the `userPrefs` box, which is excluded from
/// [HiveService.cacheSchemaBoxes] — the dismissal survives every cache
/// schema bump. Surviving the wipe is the entire point: once the user has
/// dismissed the post-session age nudge, we must never show it again (the
/// age-35 fallback is a valid steady state).
const String _agePromptDismissedKey = 'age_prompt_dismissed_at';

/// Sync-readable preference for "has the user dismissed the post-session
/// age prompt?" Backed by [HiveService.userPrefs] so the read is O(1) and
/// available before the first frame paints.
///
/// Mirrors [BodyweightPromptDismissalNotifier]: the box is opened during
/// `HiveService.init()` (which runs before `runApp`), so calling
/// `Hive.box(HiveService.userPrefs)` from `build()` is safe — no async race
/// against box-opening. A sync `Notifier` (not `AsyncNotifier`) keeps the
/// post-session gating call site + widget tests trivial.
class AgePromptDismissalNotifier extends Notifier<bool> {
  @override
  bool build() {
    final box = Hive.box<dynamic>(HiveService.userPrefs);
    final stored = box.get(_agePromptDismissedKey);
    return stored != null;
  }

  /// Persist the dismissal forever. Idempotent — repeated calls overwrite
  /// the timestamp, which is fine because reads only care about presence.
  Future<void> markDismissed() async {
    final box = Hive.box<dynamic>(HiveService.userPrefs);
    await box.put(
      _agePromptDismissedKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    state = true;
  }
}

final agePromptDismissalProvider =
    NotifierProvider<AgePromptDismissalNotifier, bool>(
      AgePromptDismissalNotifier.new,
    );
