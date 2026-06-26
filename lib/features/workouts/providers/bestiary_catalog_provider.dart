import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/bestiary_catalog.dart';

/// The fully-parsed bestiary content, loaded once from the shipped JSON
/// assets and cached in-process.
///
/// **Why a [FutureProvider]:** mirrors `titleCatalogProvider` — the catalog
/// is immutable shipped content, loaded lazily via `rootBundle`, parsed once
/// and reused for the app lifetime ([BestiaryCatalog.load] holds its own
/// process-scoped cache). A `FutureProvider` exposes that one-shot load to
/// the UI without re-parsing JSON on every read. Consumers (`BestiaryResolver`
/// construction at the post-session share seam) `read` the resolved value.
final bestiaryCatalogProvider = FutureProvider<BestiaryCatalog>((ref) {
  return BestiaryCatalog.load();
});
