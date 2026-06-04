import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Thin static gating wrapper around Sentry. Call sites use this instead of
/// `Sentry.captureException` / `Sentry.addBreadcrumb` directly so the
/// "Send crash reports" opt-out toggle can short-circuit all sends from a
/// single place.
///
/// Initialized to enabled. `main.dart` should call `setEnabled` after reading
/// the persisted flag from Hive, and the Profile screen toggle calls it when
/// the user flips the switch.
/// Signature for the function used to forward a captured exception to the
/// Sentry SDK. Production code uses [Sentry.captureException]; tests can
/// swap this out via [SentryReport.debugSetCaptureFn] to assert that the
/// enabled path actually forwards.
typedef SentryCaptureFn =
    Future<SentryId> Function(Object error, {StackTrace? stackTrace});

/// Signature for the function used to forward an in-memory breadcrumb to
/// the Sentry SDK. Production code uses [Sentry.addBreadcrumb]; tests can
/// swap this out via [SentryReport.debugSetBreadcrumbFn] to assert that
/// the enabled path actually forwards (mirrors [SentryCaptureFn]).
typedef SentryBreadcrumbFn = void Function(Breadcrumb crumb);

class SentryReport {
  SentryReport._();

  static bool _enabled = true;
  static SentryCaptureFn _captureFn = _defaultCaptureFn;
  static SentryBreadcrumbFn _breadcrumbFn = _defaultBreadcrumbFn;

  static Future<SentryId> _defaultCaptureFn(
    Object error, {
    StackTrace? stackTrace,
  }) {
    return Sentry.captureException(error, stackTrace: stackTrace);
  }

  static void _defaultBreadcrumbFn(Breadcrumb crumb) {
    Sentry.addBreadcrumb(crumb);
  }

  /// Whether Sentry sends are currently enabled.
  static bool get isEnabled => _enabled;

  /// Injects an alternate capture function for tests. Pass `null` to reset
  /// to the production Sentry forwarding path.
  @visibleForTesting
  static void debugSetCaptureFn(SentryCaptureFn? fn) {
    _captureFn = fn ?? _defaultCaptureFn;
  }

  /// Injects an alternate breadcrumb-forwarding function for tests. Pass
  /// `null` to reset to the production Sentry forwarding path. Used to
  /// assert that an `addBreadcrumb` call site actually fires (callers care
  /// about the user-visible Sentry trail, not just that the static method
  /// was hit).
  @visibleForTesting
  static void debugSetBreadcrumbFn(SentryBreadcrumbFn? fn) {
    _breadcrumbFn = fn ?? _defaultBreadcrumbFn;
  }

  /// Enable or disable Sentry sends at runtime.
  ///
  /// Disabling also clears any breadcrumbs already buffered in the Sentry
  /// scope so that the tracker does not hold on to event trails from the
  /// pre-disable session. Re-enabling starts with a fresh breadcrumb buffer.
  static void setEnabled(bool value) {
    final wasEnabled = _enabled;
    _enabled = value;
    if (wasEnabled && !value) {
      // Drop any in-memory breadcrumbs so they are not attached to a later
      // event after the user opts out. Best-effort: if Sentry is not yet
      // initialised (DSN missing) the call is a no-op.
      try {
        Sentry.configureScope((scope) => scope.clearBreadcrumbs());
      } catch (_) {
        // Never let Sentry's own failures bubble up.
      }
    }
  }

  /// Reports an exception to Sentry if enabled, otherwise no-op.
  static Future<void> captureException(
    Object error, {
    StackTrace? stackTrace,
  }) async {
    if (!_enabled) return;
    try {
      await _captureFn(error, stackTrace: stackTrace);
    } catch (_) {
      // Never let Sentry's own failures bubble up.
    }
  }

  /// Adds a breadcrumb if enabled, otherwise no-op.
  ///
  /// ## PII POLICY — READ BEFORE ADDING A NEW CALL SITE
  ///
  /// The `data` map is written to Sentry verbatim and is NOT PII-scanned
  /// the way `message` is in `beforeBreadcrumb`. You MUST only put typed
  /// IDs (`workout_id`, `routine_id`, `exercise_id`, etc.), enums, and
  /// bounded numeric values in `data`.
  ///
  /// NEVER put:
  /// - user email, display name, bio, or any free-form user input
  /// - session tokens, refresh tokens, or API keys
  /// - full URLs, file paths, or anything that could contain PII
  ///
  /// In debug mode we assert that no string value in `data` contains `@`
  /// so a careless new call site is caught locally. Release builds have
  /// a backup scan in `sentry_init.dart`'s `beforeBreadcrumb` that
  /// redacts any crumb whose `data` values contain `@`.
  static void addBreadcrumb({
    required String category,
    required String message,
    Map<String, Object?>? data,
    SentryLevel level = SentryLevel.info,
  }) {
    if (!_enabled) return;
    // Debug-mode guard: catch accidental PII in breadcrumb data at the
    // call site. Runs only when `assert` is active (debug/profile builds).
    assert(() {
      if (data == null) return true;
      for (final entry in data.entries) {
        final value = entry.value;
        if (value is String && value.contains('@')) {
          throw StateError(
            'SentryReport.addBreadcrumb: data["${entry.key}"] looks like '
            'it contains PII (@ found in string value "$value"). See the '
            'PII policy doc on SentryReport.addBreadcrumb.',
          );
        }
      }
      return true;
    }());
    try {
      _breadcrumbFn(
        Breadcrumb(
          category: category,
          message: message,
          data: data,
          level: level,
        ),
      );
    } catch (_) {
      // Never let Sentry's own failures bubble up.
    }
  }
}
