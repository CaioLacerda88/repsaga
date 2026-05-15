import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/local_storage/hive_service.dart';

/// Hive key (in [HiveService.userPrefs]) where the bodyweight-prompt
/// dismissal timestamp lives.
///
/// Stored as ISO8601 UTC string (`DateTime.now().toUtc().toIso8601String()`).
/// We store a timestamp instead of a bare bool so a future "remind me again
/// in 30 days" / re-prompt-on-major-version-bump policy can read the
/// dismissal age without a schema migration. Today only presence/absence
/// matters: any non-null value means dismissed forever.
///
/// Lives in the `userPrefs` box, which is excluded from
/// [HiveService.cacheSchemaBoxes] — the dismissal survives every cache
/// schema bump (24c-2 wipe semantics). Surviving the wipe is the entire
/// point of this preference: once the user has dismissed the prompt we
/// must never show it again, even if the model layer's cache version
/// changes underneath.
const String _bodyweightPromptDismissedKey = 'bodyweight_prompt_dismissed_at';

/// Sync-readable preference for "has the user dismissed the bodyweight
/// prompt?" Backed by [HiveService.userPrefs] so the read is O(1) and
/// available before the first frame paints.
///
/// Mirrors the [crashReportsEnabledProvider] pattern: the box is opened
/// during `HiveService.init()` (which runs before `runApp`), so calling
/// `Hive.box(HiveService.userPrefs)` from `build()` is safe — no async
/// race against box-opening.
///
/// **Why a sync `Notifier` instead of `AsyncNotifier`:** the box is
/// guaranteed open by the time any UI consumer reads this provider;
/// gating UI on a `FutureProvider` here would force every caller into
/// `AsyncValue.when` for a value that's available immediately. Sync
/// reads keep the call sites (the active-workout coordinator + widget
/// tests) trivial.
class BodyweightPromptDismissalNotifier extends Notifier<bool> {
  @override
  bool build() {
    final box = Hive.box<dynamic>(HiveService.userPrefs);
    final stored = box.get(_bodyweightPromptDismissedKey);
    return stored != null;
  }

  /// Persist the dismissal forever. Idempotent — calling repeatedly is
  /// safe (overwrites the timestamp with a fresher one, which is fine
  /// because today's reads only care about presence).
  ///
  /// Updates the in-memory state synchronously after the Hive write
  /// completes so subscribers (the active-workout coordinator's
  /// `ref.listen`) react immediately without waiting for a rebuild
  /// triggered by box-watch events.
  Future<void> markDismissed() async {
    final box = Hive.box<dynamic>(HiveService.userPrefs);
    await box.put(
      _bodyweightPromptDismissedKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    state = true;
  }
}

final bodyweightPromptDismissalProvider =
    NotifierProvider<BodyweightPromptDismissalNotifier, bool>(
      BodyweightPromptDismissalNotifier.new,
    );
