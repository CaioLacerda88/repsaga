import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// `share_plus` re-exports `XFile` from `cross_file`; importing both would
// trigger an `unnecessary_import` info (fatal under CI's `--fatal-infos`).
// `XFile` is read off the same import that defines `ShareResult`.
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/data_export_service.dart';

/// Hands the prepared JSON file to the native share sheet. Hoisted to a
/// top-level typedef so the export-job controller can run under a fake
/// `FileShareSink` in unit/widget tests without touching the
/// `share_plus` plugin channel.
///
/// Matches the shape of `FileShareSink` used by `ShareService` (Phase 30b)
/// so a future consolidation can collapse them — kept separate for now
/// because the share-card pipeline + data export have different error /
/// retry semantics.
typedef DataExportShareSink =
    Future<ShareResult> Function(List<XFile> files, {String? text});

/// Result payload emitted by [ExportJobController] on a successful export.
/// Stays minimal — the caller (UI snackbar) only needs to know the export
/// happened; the actual file already went to the share sheet by the time
/// this is emitted.
class ExportResult {
  const ExportResult({required this.filename, required this.byteLength});

  /// Generated filename in the form `repsaga_export_YYYY-MM-DD.json`.
  final String filename;

  /// Size of the JSON payload in bytes. Used by widget tests to assert a
  /// non-empty export landed without comparing the full string.
  final int byteLength;
}

/// DI seam for [DataExportService]. The repository pattern would normally
/// wire this through a `BaseRepository` subclass, but the export service
/// queries multiple feature tables and intentionally owns its own
/// per-stage error wrapping (see [DataExportService] docstring) — it's a
/// data-layer aggregator, not a single-table repository.
final dataExportServiceProvider = Provider<DataExportService>((ref) {
  return DataExportService(Supabase.instance.client);
});

/// DI seam for the share sink. Defaults to `share_plus`'s
/// `SharePlus.instance.share` — same shape `ShareService._defaultFileShareSink`
/// uses for the share-card flow. Overridden in widget tests with a fake that
/// records the file/text payload without invoking the plugin channel.
final dataExportShareSinkProvider = Provider<DataExportShareSink>((ref) {
  return (List<XFile> files, {String? text}) =>
      SharePlus.instance.share(ShareParams(files: files, text: text));
});

/// Coordinator for the "Export my data" flow.
///
/// **State machine.** `AsyncData(null)` (idle) → `AsyncLoading` (data
/// fetch + serialize + share) → `AsyncData(ExportResult)` on success /
/// `AsyncError` on failure. The `AsyncValue<ExportResult?>` wrapper gives
/// the UI a single shape to render against (consistent with the rest of
/// the app's notifier surface).
///
/// **Why a plain `Notifier<AsyncValue<…>>` instead of `AsyncNotifier`.**
/// `AsyncNotifier.build` is the right shape for "I produce a value on
/// mount" semantics; this controller produces a value on user action.
/// Modeling it as an explicit notifier whose `build` returns `idle` and
/// whose method transitions to `loading` / `data` matches the share-card
/// controller's discipline (PR #263) and keeps the action lifecycle out of
/// the framework's automatic-rebuild machinery.
class ExportJobController extends Notifier<AsyncValue<ExportResult?>> {
  @override
  AsyncValue<ExportResult?> build() => const AsyncValue.data(null);

  /// Drive the full export pipeline: fetch + serialize + create the XFile
  /// + hand to the share sheet. Emits `AsyncLoading` while in flight,
  /// `AsyncData(ExportResult)` on success, `AsyncError` on failure.
  ///
  /// Idempotent reentry: a second call while one is in flight short-
  /// circuits (no-op). The UI tile's `onTap` is gated on
  /// `!state.isLoading` regardless, but the structural guard belongs
  /// here too — if a future shortcut re-fires the action while a previous
  /// run is still encoding, we don't want to interleave two share-sheet
  /// hand-offs.
  Future<void> exportAndShare(String userId) async {
    if (state.isLoading) return;

    state = const AsyncValue.loading();
    try {
      final service = ref.read(dataExportServiceProvider);
      final shareSink = ref.read(dataExportShareSinkProvider);

      final json = await service.buildJsonExport(userId);
      final filename = _buildFilename();
      final bytes = utf8.encode(json);

      // `XFile.fromData` keeps the payload in memory — no temp file on
      // disk. share_plus serializes it through the platform channel which
      // the OS persists for the receiving app. Avoids the cleanup
      // complexity of path_provider + manual file deletion.
      //
      // **`path` AND `name`** — cross_file's IO implementation ignores
      // the `name:` parameter (a web-only artifact) and instead derives
      // the filename from `path.split(pathSeparator).last`. Without
      // passing `path`, `XFile.name` resolves to the empty string and
      // share_plus surfaces a nameless attachment to the receiving app.
      // Passing the bare filename as `path` makes the IO platform layer
      // expose the right name AND keeps the web layer using its `name:`
      // hint.
      final file = XFile.fromData(
        bytes,
        path: filename,
        name: filename,
        mimeType: 'application/json',
      );

      await shareSink(<XFile>[file], text: null);

      state = AsyncValue.data(
        ExportResult(filename: filename, byteLength: bytes.length),
      );
    } catch (e, st) {
      // ExportException is what the service throws; anything else (e.g.
      // a share_plus platform exception) lands here too and surfaces as
      // an opaque error to the UI snackbar.
      state = AsyncValue.error(e, st);
    }
  }

  /// Reset to the initial state. Called by the UI after the success /
  /// error snackbar shows so the next tap starts fresh.
  void reset() {
    state = const AsyncValue.data(null);
  }

  /// Build the export filename — `repsaga_export_YYYY-MM-DD.json` in the
  /// user's LOCAL timezone (per spec). The date prefix mirrors
  /// `DateTime.now().toIso8601String().split('T')[0]` so the filename is
  /// stable across the same local day regardless of clock skew.
  static String _buildFilename() {
    final date = DateTime.now().toIso8601String().split('T')[0];
    return 'repsaga_export_$date.json';
  }
}

/// Top-level provider exposing the export controller.
final exportJobProvider =
    NotifierProvider<ExportJobController, AsyncValue<ExportResult?>>(
      ExportJobController.new,
    );
