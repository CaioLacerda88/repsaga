sealed class AppException implements Exception {
  const AppException(this.message);

  /// Internal message for developer logging. May contain sensitive details
  /// such as table names or SQL error codes. **Never display to users.**
  final String message;

  /// User-safe message suitable for display in the UI.
  /// Subclasses override this to provide appropriate fallback text.
  String get userMessage => 'Something went wrong. Please try again.';

  @override
  String toString() => '$runtimeType: $message';
}

class AuthException extends AppException {
  const AuthException(super.message, {required this.code});

  final String code;

  @override
  String get userMessage => 'Authentication error. Please log in again.';
}

class DatabaseException extends AppException {
  const DatabaseException(super.message, {required this.code});

  final String code;

  @override
  String get userMessage => 'Something went wrong. Please try again.';
}

class NetworkException extends AppException {
  const NetworkException(super.message);

  @override
  String get userMessage =>
      'No internet connection. Please check your network.';
}

/// Raised when an outbound request did not complete within its allotted
/// budget. This is intentionally a sibling of [NetworkException] (not a
/// subtype): the user-facing copy and the recovery affordance differ — a
/// timed-out request is usually retryable as-is, whereas a no-connection
/// state typically requires the user to fix their network first.
///
/// Naming note: `dart:async` also exports a `TimeoutException`. Callers that
/// need to refer to both must disambiguate via a prefixed import, e.g.
/// `import 'dart:async' as async;` and `async.TimeoutException`.
class TimeoutException extends AppException {
  const TimeoutException([super.message = 'Request timed out.']);

  @override
  String get userMessage => 'Request timed out. Please try again.';
}

class ValidationException extends AppException {
  const ValidationException(super.message, {required this.field});

  final String field;

  /// Validation messages are user-generated and safe to display.
  @override
  String get userMessage => message;
}

/// Raised when the user-data JSON export pipeline fails at one of its
/// per-table fetch stages or the final serialization. Carries [stage] so
/// the dev log pinpoints which table broke, while [userMessage] stays
/// generic so the snackbar never leaks the underlying Postgres / network
/// error to the UI.
///
/// **Cluster reference:** `data-protection-compliance` — the in-app
/// portability mechanism the Privacy Policy §6 row promises is built on
/// top of [DataExportService], and every fetch path that contributes to
/// the export translates its failure into this exception so the surface
/// only ever shows one user-safe error category.
class ExportException extends AppException {
  const ExportException(super.message, {required this.stage, this.cause});

  /// Logical label for the failing step — typically the table name (e.g.
  /// `'workouts'`, `'xp_events'`) or `'serialize'` for the final
  /// `jsonEncode` step. Used for dev logging and Sentry breadcrumbs only;
  /// never displayed to the user.
  final String stage;

  /// Original error (PostgrestException, NetworkException, etc.) preserved
  /// for the dev log so the underlying cause is not lost. Never shown to
  /// the user — [userMessage] is the safe surface.
  final Object? cause;

  @override
  String get userMessage =>
      "We couldn't prepare your data export. Please try again.";
}
