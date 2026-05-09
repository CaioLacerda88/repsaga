import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/connectivity/recovery_recorder_provider.dart';
import '../data/titles_repository.dart';
import '../models/title.dart';

/// Single instance of the titles repository. Lazily resolves the Supabase
/// client and the default `rootBundle` for asset reads.
final titlesRepositoryProvider = Provider<TitlesRepository>((ref) {
  return TitlesRepository(
    Supabase.instance.client,
    recoveryRecorder: ref.watch(recoveryRecorderProvider),
  );
});

/// The full v1 title catalog (78 entries) loaded from the shipped asset.
/// One-shot future — the asset is immutable. Other providers can `read`
/// this for slug lookups without re-parsing JSON each time.
final titleCatalogProvider = FutureProvider<List<Title>>((ref) {
  return ref.read(titlesRepositoryProvider).loadCatalog();
});

/// UI-shaped row for the Titles screen — pairs a [Title] catalog entry with
/// its per-user earned state.
class EarnedTitleEntry {
  const EarnedTitleEntry({
    required this.title,
    required this.earnedAt,
    required this.isActive,
  });

  final Title title;
  final DateTime earnedAt;

  /// True for the single equipped row enforced by
  /// `earned_titles_one_active` UNIQUE INDEX.
  final bool isActive;
}

/// Per-user list of earned titles, joined against the catalog.
///
/// **Why a [FutureProvider] instead of a [StreamProvider]:** WIP §13 (the
/// Phase 18c implementation checklist line that originally read
/// "earned_titles_provider — Stream of earned titles") is overridden here
/// because there's no realtime push channel for `earned_titles` in v1.
/// Rows are written server-side inside `record_set_xp` (transactional with
/// the workout save) and equipped via UPDATE from this client. Equip
/// toggles fan out through `container.invalidate(earnedTitlesProvider)` on
/// the equipping client; other devices catch up on next entry into the
/// Titles screen. A `Stream` would imply realtime, which isn't wired (and
/// isn't needed for v1's solo-lifter audience).
///
/// Skipped server-side rows whose slug isn't in the shipped catalog (a
/// future-catalog row replayed against an old client) — those would be
/// orphaned UI entries with no display copy. Logged in debug builds via
/// stdout; production silently filters.
final earnedTitlesProvider = FutureProvider<List<EarnedTitleEntry>>((
  ref,
) async {
  final repo = ref.read(titlesRepositoryProvider);
  final rows = await repo.getEarnedTitles();
  if (rows.isEmpty) return const <EarnedTitleEntry>[];

  final catalog = await ref.watch(titleCatalogProvider.future);
  final bySlug = <String, Title>{for (final t in catalog) t.slug: t};

  final entries = <EarnedTitleEntry>[];
  for (final row in rows) {
    final title = bySlug[row.titleId];
    if (title == null) continue; // future-catalog row, no display copy.
    entries.add(
      EarnedTitleEntry(
        title: title,
        earnedAt: row.earnedAt,
        isActive: row.isActive,
      ),
    );
  }
  return entries;
});

/// Convenience: the slug of the currently equipped title, or null. Powers
/// the character sheet's title sub-label without forcing it to walk the
/// full earned-titles list.
final equippedTitleSlugProvider = FutureProvider<String?>((ref) {
  return ref.read(titlesRepositoryProvider).getActiveTitleSlug();
});
