import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/local_storage/hive_service.dart';

/// Hive key (in [HiveService.userPrefs]) where the slug of the most-recently
/// surfaced beast is persisted.
///
/// Drives the `BestiaryResolver`'s client-side 1-deep "last beast" no-repeat
/// guard (spec §5): on a hash collision the resolver advances to the next
/// variant so the same (line, tier) never shows the same creature two
/// sessions running. Lives in `userPrefs` (durable, survives cache schema
/// bumps) — losing it only costs one possible repeat, never correctness.
const String _lastBeastSlugKey = 'last_beast_slug';

/// Sync-readable accessor for the last-surfaced beast slug. Backed by
/// [HiveService.userPrefs] so the read is O(1) and available before the
/// first frame paints (the box is opened in `HiveService.init()`, ahead of
/// `runApp`).
///
/// **Read before resolving, write after sharing.** The post-session share
/// seam reads [LastBeastSlugNotifier.value] to feed the resolver's
/// `lastBeastSlug`, then calls [record] with the resolved beast's slug once
/// the user actually shares — so the guard reflects beasts the user has
/// SEEN/shared, not every card merely composed.
class LastBeastSlugNotifier extends Notifier<String?> {
  @override
  String? build() {
    final box = Hive.box<dynamic>(HiveService.userPrefs);
    return box.get(_lastBeastSlugKey) as String?;
  }

  /// Persist [slug] as the most-recently surfaced beast. Idempotent — a
  /// repeated record of the same slug no-ops the emit.
  Future<void> record(String slug) async {
    if (state == slug) return;
    final box = Hive.box<dynamic>(HiveService.userPrefs);
    await box.put(_lastBeastSlugKey, slug);
    state = slug;
  }
}

final lastBeastSlugProvider = NotifierProvider<LastBeastSlugNotifier, String?>(
  LastBeastSlugNotifier.new,
);
