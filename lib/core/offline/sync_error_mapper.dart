import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../l10n/app_localizations.dart';
import '../exceptions/app_exception.dart' as app;
import '../observability/sentry_report.dart';
import 'pending_action.dart';

/// Maps a thrown sync error to a user-safe, localized message.
///
/// **Why this exists (BUG-042):** the offline-sync queue used to render
/// `error.toString()` directly in the "Sincronização Pendente" sheet, which
/// leaked Postgres constraint names, Dart cast-error internals, and
/// table/column names to end users. That's both a bad UX (nobody understands
/// `DatabaseException: insert or update on table "personal_records" violates
/// foreign key constraint "personal_records_set_id_fkey"`) and an information
/// disclosure issue (OWASP A04:2021 — exposing internal schema).
///
/// **BUG-008:** also classifies the error into a [SyncErrorCategory] so the
/// pending-sync sheet can pick between retry and dismiss CTAs.
///
/// **Contract:**
/// - The raw exception (with full stack) goes to `developer.log()` and Sentry
///   so we can still diagnose production issues.
/// - The UI receives **only** the localized return value. There is no path
///   from `error.toString()` to the user.
/// - One mapping function, used at every UI boundary that surfaces sync
///   errors. Don't scatter `try/catch + l10n` across widgets — one place.
///
/// All copy is sourced from `app_pt.arb` / `app_en.arb` — pt-BR is the
/// canonical authoring locale per CLAUDE.md.
class SyncErrorMapper {
  // Static-only utility — instantiation is meaningless; the private
  // constructor matches the prevailing codebase idiom (AppNumberFormat,
  // ErrorMapper, AppTheme, etc.) for utility classes.
  const SyncErrorMapper._();

  /// Returns a user-safe message for [error], localized via [l10n].
  ///
  /// Side effect: logs the raw exception via `debugPrint` and forwards
  /// it as a Sentry breadcrumb. The caller does not need to log separately.
  /// cluster: developer-log-invisible-logcat — `developer.log` is invisible
  /// in adb logcat; `debugPrint` reaches the on-device log stream.
  static String toUserMessage(AppLocalizations l10n, Object error) {
    // Always log the raw error — this is what we need for diagnosis and
    // it MUST stay out of the UI.
    debugPrint('[SyncErrorMapper] Sync error: $error');
    SentryReport.addBreadcrumb(
      category: 'sync.error',
      message: 'Sync error mapped to user',
      data: {'error_class': error.runtimeType.toString()},
    );

    return _lookup(error).message(l10n);
  }

  /// Pure classification — no logging, no side effects. Exposed for tests
  /// that pin each exception class to its expected localized message
  /// without observing log/sentry side effects.
  static String classify(AppLocalizations l10n, Object error) =>
      _lookup(error).message(l10n);

  /// Returns the [SyncErrorCategory] for [error].
  ///
  /// Shares the same dispatch table as [classify] / [toUserMessage] so the
  /// category and l10n key for any given exception class can never drift —
  /// adding a new exception type is a single new entry in [_table] that
  /// produces both outputs.
  ///
  /// This is the value [SyncService] writes to [PendingAction.errorCategory]
  /// on each failed drain attempt so the pending-sync sheet (BUG-008) can
  /// pick between retry vs dismiss without re-classifying.
  static SyncErrorCategory classifyCategory(Object error) =>
      _lookup(error).category;

  /// Find the first table entry whose matcher accepts [error]. Falls back to
  /// the unknown bucket if nothing matches.
  static _Entry _lookup(Object error) {
    for (final entry in _table) {
      if (entry.matches(error)) return entry;
    }
    return _unknown;
  }

  /// Single source of truth for exception class → category + l10n key.
  ///
  /// Order is significant: more specific matchers MUST come before broader
  /// ones. Adding a new exception type is one row that participates in both
  /// `classifyCategory` and `classify` — the two cannot drift.
  static final List<_Entry> _table = <_Entry>[
    // Auth errors — wrapped AppException and raw supabase.AuthException
    // funnel into the same session-expired message + session category.
    _Entry(
      matches: (e) => e is app.AuthException,
      category: SyncErrorCategory.session,
      message: (l10n) => l10n.syncErrorSessionExpired,
    ),
    _Entry(
      matches: (e) => e is supabase.AuthException,
      category: SyncErrorCategory.session,
      message: (l10n) => l10n.syncErrorSessionExpired,
    ),

    // Network / offline / timeout — softer copy because the user's data is
    // safe in the queue and a retry once connectivity is back will succeed.
    _Entry(
      matches: (e) => e is SocketException,
      category: SyncErrorCategory.network,
      message: (l10n) => l10n.syncErrorOffline,
    ),
    _Entry(
      matches: (e) => e is TimeoutException,
      category: SyncErrorCategory.network,
      message: (l10n) => l10n.syncErrorOffline,
    ),
    _Entry(
      matches: (e) => e is HttpException,
      category: SyncErrorCategory.network,
      message: (l10n) => l10n.syncErrorOffline,
    ),
    _Entry(
      matches: (e) => e is app.NetworkException,
      category: SyncErrorCategory.network,
      message: (l10n) => l10n.syncErrorOffline,
    ),

    // Postgrest / database / type errors — structural. The mapper still
    // returns the generic "we'll retry" copy (BUG-042 information-
    // disclosure contract: never expose constraint names or table names),
    // but the category drives the sheet to show "Dispensar" instead of
    // "Tentar novamente" because retrying without a code change won't fix
    // an FK violation, RLS denial, unique-constraint collision, or cast
    // failure.
    _Entry(
      matches: (e) => e is supabase.PostgrestException,
      category: SyncErrorCategory.structural,
      message: (l10n) => l10n.syncErrorRetryGeneric,
    ),
    _Entry(
      matches: (e) => e is app.DatabaseException,
      category: SyncErrorCategory.structural,
      message: (l10n) => l10n.syncErrorRetryGeneric,
    ),
    _Entry(
      matches: (e) => e is TypeError,
      category: SyncErrorCategory.structural,
      message: (l10n) => l10n.syncErrorRetryGeneric,
    ),
  ];

  /// Catch-all for exception classes the table does not match. Treated as
  /// non-terminal so the user keeps a retry CTA — a genuinely unknown error
  /// might be a one-off plugin crash that retry would resolve. If the
  /// underlying issue is structural the next attempt will surface a more
  /// specific error class that the table catches and routes to "Dispensar".
  static final _Entry _unknown = _Entry(
    matches: (_) => true,
    category: SyncErrorCategory.unknown,
    message: (l10n) => l10n.syncErrorUnknown,
  );
}

/// One row of the dispatch table — pairs a runtime-type matcher with the
/// category and localized message that exception class must produce.
///
/// Bundled together so adding a new exception type is one new [_Entry]; the
/// public surface ([SyncErrorMapper.classifyCategory] and
/// [SyncErrorMapper.classify]) cannot diverge structurally.
class _Entry {
  _Entry({
    required this.matches,
    required this.category,
    required this.message,
  });

  /// Predicate that returns true when this entry should handle [error].
  /// Order in [SyncErrorMapper._table] is significant — the first matching
  /// entry wins, so more specific matchers must come before broader ones.
  final bool Function(Object error) matches;

  /// The [SyncErrorCategory] this exception class maps to. Drives the
  /// pending-sync sheet's CTA selection (retry vs dismiss).
  final SyncErrorCategory category;

  /// L10n key resolver. Takes the active [AppLocalizations] and returns the
  /// user-safe message the UI renders. MUST be a fixed l10n key — never
  /// `error.toString()` or any concatenation that could leak schema names
  /// or stack details (BUG-042 information-disclosure contract).
  final String Function(AppLocalizations l10n) message;
}
