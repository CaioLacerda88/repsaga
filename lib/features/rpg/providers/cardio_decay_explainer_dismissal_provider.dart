import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/local_storage/hive_service.dart';

/// Hive key (in [HiveService.userPrefs]) where the one-time cardio-decay
/// explainer dismissal timestamp lives.
///
/// Stored as an ISO8601 UTC string. We persist a timestamp rather than a
/// bare bool so a future "re-surface on a major version bump" policy can read
/// the dismissal age without a schema migration. Today only presence matters:
/// any non-null value means dismissed forever.
///
/// Lives in the `userPrefs` box, which is excluded from
/// [HiveService.cacheSchemaBoxes] — the dismissal survives every cache schema
/// bump. Surviving the wipe is the entire point: the stats-decay explainer is
/// a one-time teaching banner; once the user has read + dismissed it, we must
/// never show it again.
const String _cardioDecayExplainerDismissedKey =
    'cardio_decay_explainer_dismissed_at';

/// Sync-readable preference for "has the user dismissed the one-time cardio
/// stats-decay explainer banner?" Backed by [HiveService.userPrefs] so the
/// read is O(1) and available before the first frame paints.
///
/// Mirrors [AgePromptDismissalNotifier]: the box is opened during
/// `HiveService.init()` (which runs before `runApp`), so calling
/// `Hive.box(HiveService.userPrefs)` from `build()` is safe — no async race
/// against box-opening. A sync `Notifier` (not `AsyncNotifier`) keeps the
/// stats-screen gating call site + widget tests trivial.
class CardioDecayExplainerDismissalNotifier extends Notifier<bool> {
  @override
  bool build() {
    final box = Hive.box<dynamic>(HiveService.userPrefs);
    final stored = box.get(_cardioDecayExplainerDismissedKey);
    return stored != null;
  }

  /// Persist the dismissal forever. Idempotent — repeated calls overwrite the
  /// timestamp, which is fine because reads only care about presence.
  Future<void> markDismissed() async {
    final box = Hive.box<dynamic>(HiveService.userPrefs);
    await box.put(
      _cardioDecayExplainerDismissedKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    state = true;
  }
}

final cardioDecayExplainerDismissalProvider =
    NotifierProvider<CardioDecayExplainerDismissalNotifier, bool>(
      CardioDecayExplainerDismissalNotifier.new,
    );
