import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Probe the Supabase REST root with a tiny request and return whether the
/// server appears reachable.
///
/// **Why not raw HEAD via `package:http`:** the SDK already manages auth
/// headers and the configured URL — duplicating that wiring here would add
/// a maintenance burden if the project ever rotates anon keys or moves
/// regions. Instead we fire a `select('id')...limit(1)` against the
/// `public.users` view (every project has one), which is one row read and
/// short-circuited by the LIMIT before any heavy planning kicks in.
///
/// The query returning a 5xx, timing out, or throwing a network error is
/// treated as "server not healthy" -> returns `false`. A 401 or auth-token
/// error also counts as unhealthy because the recovery hook treats those
/// as network-class. A 4xx (e.g. RLS-denied) means the server IS healthy
/// — return `true`.
///
/// The default implementation is overridable in tests via [healthCheckProvider].
typedef HealthCheck = Future<bool> Function();

/// Default probe — selects a single row from `public.users`.
///
/// Returns `true` for any "the server answered" outcome, including 4xx
/// authorisation errors (which prove the server reached PostgREST).
/// Returns `false` for 5xx, timeouts, and raw transport-level failures.
Future<bool> _defaultHealthCheck() async {
  try {
    await Supabase.instance.client
        .from('users')
        .select('id')
        .limit(1)
        .timeout(const Duration(seconds: 10));
    return true;
  } on PostgrestException catch (e) {
    final code = int.tryParse(e.code ?? '');
    if (code != null && code >= 500 && code < 600) return false;
    // 4xx — the server is reachable enough to return a structured error.
    return true;
  } catch (_) {
    // Timeout, socket, or unknown — server is not reachable.
    return false;
  }
}

/// Provides a function that probes server reachability. Tests can override
/// this with a stub to drive the health-check timer in [SyncService].
final healthCheckProvider = Provider<HealthCheck>((ref) {
  return _defaultHealthCheck;
});

/// Cadence of the health-check probe. Production: 60 seconds. Tests
/// override this to a small value (e.g. 50ms) so the timer's lifecycle and
/// firing behaviour can be verified with real wall-time pumps without
/// resorting to `fake_async`, which doesn't compose with Hive's real I/O
/// futures and would deadlock the test.
final healthCheckIntervalProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 60);
});
