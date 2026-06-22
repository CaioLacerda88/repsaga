import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/exceptions/app_exception.dart' as app;
import 'package:repsaga/core/offline/sync_error_classifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

void main() {
  group('SyncErrorClassifier', () {
    // PRODUCTION ERROR SHAPES. PostgrestException.code (and the
    // app.DatabaseException.code that ErrorMapper copies from it) is the
    // Postgres SQLSTATE / a PGRST* code — NEVER a parseable HTTP int. The
    // earlier suite injected mock HTTP codes ('400'/'409') that the runtime
    // never emits, masking the dead terminal fast-path. These cases use the
    // real codes. cluster: classifier-keyed-on-http-not-sqlstate.
    group('isTerminal', () {
      // --- Terminal SQLSTATEs (deterministic — identical replay always fails)
      test('returns true for 22P02 invalid_text_representation '
          '(malformed UUID in payload)', () {
        const error = supabase.PostgrestException(
          message: 'invalid input syntax for type uuid',
          code: '22P02',
        );
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns true for 23502 not_null_violation', () {
        const error = supabase.PostgrestException(
          message: 'null value in column violates not-null constraint',
          code: '23502',
        );
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns true for 23503 foreign_key_violation', () {
        const error = supabase.PostgrestException(
          message: 'insert or update violates foreign key constraint',
          code: '23503',
        );
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns true for 23505 unique_violation', () {
        const error = supabase.PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
        );
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns true for 23514 check_violation', () {
        const error = supabase.PostgrestException(
          message: 'new row violates check constraint',
          code: '23514',
        );
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns true for 42501 insufficient_privilege (RLS denial)', () {
        const error = supabase.PostgrestException(
          message: 'new row violates row-level security policy',
          code: '42501',
        );
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns true for 42P01 undefined_table', () {
        const error = supabase.PostgrestException(
          message: 'relation does not exist',
          code: '42P01',
        );
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns true for 42703 undefined_column', () {
        const error = supabase.PostgrestException(
          message: 'column does not exist',
          code: '42703',
        );
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns true for PGRST202 (RPC not found in schema cache)', () {
        const error = supabase.PostgrestException(
          message: 'Could not find the function in the schema cache',
          code: 'PGRST202',
        );
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns true for PGRST204 (column not found)', () {
        const error = supabase.PostgrestException(
          message: 'Column not found',
          code: 'PGRST204',
        );
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test(
        'returns false for PGRST0xx connection family (transient, retryable)',
        () {
          // PGRST003 = timed out acquiring a pooled connection; the PGRST0xx
          // connection group resolves once the DB/pool recovers, so it must
          // NOT be swept into terminal alongside PGRST1xx/2xx/3xx.
          const error = supabase.PostgrestException(
            message: 'Timed out acquiring connection from the pool',
            code: 'PGRST003',
          );
          expect(SyncErrorClassifier.isTerminal(error), isFalse);
        },
      );

      // --- Transient SQLSTATEs (retry can succeed — must NOT be terminal)
      test('returns false for 40001 serialization_failure (retryable)', () {
        const error = supabase.PostgrestException(
          message: 'could not serialize access due to concurrent update',
          code: '40001',
        );
        expect(SyncErrorClassifier.isTerminal(error), isFalse);
      });

      test('returns false for 40P01 deadlock_detected (retryable)', () {
        const error = supabase.PostgrestException(
          message: 'deadlock detected',
          code: '40P01',
        );
        expect(SyncErrorClassifier.isTerminal(error), isFalse);
      });

      test('returns false for 55P03 lock_not_available (retryable)', () {
        const error = supabase.PostgrestException(
          message: 'could not obtain lock',
          code: '55P03',
        );
        expect(SyncErrorClassifier.isTerminal(error), isFalse);
      });

      test('returns false for 57014 query_canceled (retryable)', () {
        const error = supabase.PostgrestException(
          message: 'canceling statement due to statement timeout',
          code: '57014',
        );
        expect(SyncErrorClassifier.isTerminal(error), isFalse);
      });

      test('returns false for 53300 too_many_connections (retryable)', () {
        const error = supabase.PostgrestException(
          message: 'too many connections',
          code: '53300',
        );
        expect(SyncErrorClassifier.isTerminal(error), isFalse);
      });

      test('returns false for 08006 connection_failure (retryable)', () {
        const error = supabase.PostgrestException(
          message: 'connection failure',
          code: '08006',
        );
        expect(SyncErrorClassifier.isTerminal(error), isFalse);
      });

      test('returns false for P0002 no_data_found (RPC raise; retryable)', () {
        // The save_workout finalize RPC raises P0002 when the workout row
        // isn't visible yet — a timing/visibility issue that can clear, not a
        // deterministic data-shape error. Conservative default keeps it
        // transient.
        const error = supabase.PostgrestException(
          message: 'Workout not found or does not belong to user',
          code: 'P0002',
        );
        expect(SyncErrorClassifier.isTerminal(error), isFalse);
      });

      test('returns false for SocketException', () {
        expect(
          SyncErrorClassifier.isTerminal(const SocketException('refused')),
          isFalse,
        );
      });

      test('returns false for TimeoutException', () {
        expect(
          SyncErrorClassifier.isTerminal(TimeoutException('timeout')),
          isFalse,
        );
      });

      test('returns false for AuthException (token auto-refresh)', () {
        expect(
          SyncErrorClassifier.isTerminal(
            const supabase.AuthException('JWT expired'),
          ),
          isFalse,
        );
      });

      test('returns false for unknown exception types', () {
        expect(SyncErrorClassifier.isTerminal(Exception('random')), isFalse);
      });

      test('returns false for PostgrestException with unrecognised code '
          '(conservative default)', () {
        const error = supabase.PostgrestException(
          message: 'some new code we have not classified',
          code: '99999',
        );
        expect(SyncErrorClassifier.isTerminal(error), isFalse);
      });

      // Wrapped app.* exception types — repository layer maps raw Supabase
      // errors into these via BaseRepository.mapException, copying the raw
      // SQLSTATE/PGRST code onto DatabaseException.code. The classifier must
      // recognise both shapes (PR1B catch-site sees the wrapped form).
      test('returns true for wrapped app.DatabaseException with 22P02', () {
        const error = app.DatabaseException('malformed uuid', code: '22P02');
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns true for wrapped app.DatabaseException with 42501 '
          '(RLS denial)', () {
        const error = app.DatabaseException('RLS denied', code: '42501');
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns true for wrapped app.DatabaseException with '
          "'deserialization' sentinel (ErrorMapper TypeError)", () {
        // ErrorMapper maps a Dart TypeError during JSON decode to
        // DatabaseException(code: 'deserialization') — a malformed payload
        // won't reshape on retry, so it's terminal.
        const error = app.DatabaseException(
          'type error',
          code: 'deserialization',
        );
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns false for wrapped app.DatabaseException with 40001 '
          '(serialization — retryable)', () {
        const error = app.DatabaseException('serialization', code: '40001');
        expect(SyncErrorClassifier.isTerminal(error), isFalse);
      });

      test("returns false for wrapped app.DatabaseException with 'unknown' "
          'sentinel (ErrorMapper fallback — conservative)', () {
        // ErrorMapper uses code 'unknown' when PostgrestException.code is
        // null. Conservative default: keep retrying.
        const error = app.DatabaseException('no code', code: 'unknown');
        expect(SyncErrorClassifier.isTerminal(error), isFalse);
      });

      test('returns false for wrapped app.NetworkException', () {
        expect(
          SyncErrorClassifier.isTerminal(
            const app.NetworkException('no connection'),
          ),
          isFalse,
        );
      });

      test('returns false for wrapped app.TimeoutException', () {
        expect(
          SyncErrorClassifier.isTerminal(const app.TimeoutException()),
          isFalse,
        );
      });

      test('returns false for wrapped app.AuthException', () {
        expect(
          SyncErrorClassifier.isTerminal(
            const app.AuthException('JWT expired', code: '401'),
          ),
          isFalse,
        );
      });
    });

    // The httpCode helper `int.tryParse`s the `code` field of the
    // code-bearing wrapped shapes (app.DatabaseException / app.AuthException)
    // and raw PostgrestException. In production the only shape whose code is a
    // real HTTP int is the AuthException family (ErrorMapper copies gotrue's
    // `statusCode`); a PostgREST/Postgres code is a SQLSTATE/PGRST string and
    // tryParse yields null for codes containing letters (e.g. `22P02`,
    // `PGRST202`). NOTE: an all-digit SQLSTATE like `42501` happens to parse —
    // but the 5xx copy consumer only acts on the 500-599 range, which no real
    // SQLSTATE falls into, so this is harmless. (Raw supabase.AuthException is
    // intentionally NOT handled here — only the app.* wrapped form is, since
    // that's what the catch sites see post-mapException.)
    group('httpCode', () {
      test('returns the HTTP code for wrapped app.AuthException', () {
        const error = app.AuthException('JWT expired', code: '401');
        expect(SyncErrorClassifier.httpCode(error), 401);
      });

      test('returns null for raw supabase.AuthException (not handled — the '
          'catch sites see the wrapped form)', () {
        const error = supabase.AuthException(
          'Invalid login credentials',
          statusCode: '400',
        );
        expect(SyncErrorClassifier.httpCode(error), isNull);
      });

      test('returns null for PostgrestException with an alphanumeric SQLSTATE '
          '(not an HTTP int)', () {
        const error = supabase.PostgrestException(
          message: 'malformed uuid',
          code: '22P02',
        );
        expect(SyncErrorClassifier.httpCode(error), isNull);
      });

      test('returns null for wrapped app.DatabaseException with an '
          'alphanumeric SQLSTATE/PGRST code', () {
        const error = app.DatabaseException('RPC missing', code: 'PGRST202');
        expect(SyncErrorClassifier.httpCode(error), isNull);
      });

      test('returns null for app.NetworkException (no HTTP code shape)', () {
        expect(
          SyncErrorClassifier.httpCode(
            const app.NetworkException('no connection'),
          ),
          isNull,
        );
      });

      test('returns null for unknown exception types', () {
        expect(SyncErrorClassifier.httpCode(Exception('random')), isNull);
      });
    });

    // The isNetworkClass helper distinguishes "the request couldn't reach a
    // healthy server" (timeout, socket-refused, DNS, 5xx, transient auth)
    // from domain errors (4xx validation, business-logic). The recovery
    // signal in `connectivityRecoveryProvider` consumes this — a domain
    // error must NOT mark the network as unhealthy, because the network was
    // healthy enough to return a structured 4xx.
    group('isNetworkClass', () {
      test('returns true for SocketException', () {
        expect(
          SyncErrorClassifier.isNetworkClass(const SocketException('refused')),
          isTrue,
        );
      });

      test('returns true for dart:async TimeoutException', () {
        expect(
          SyncErrorClassifier.isNetworkClass(TimeoutException('timeout')),
          isTrue,
        );
      });

      test('returns true for wrapped app.NetworkException', () {
        expect(
          SyncErrorClassifier.isNetworkClass(
            const app.NetworkException('no connection'),
          ),
          isTrue,
        );
      });

      test('returns true for wrapped app.TimeoutException', () {
        expect(
          SyncErrorClassifier.isNetworkClass(const app.TimeoutException()),
          isTrue,
        );
      });

      test('returns true for 5xx PostgrestException (server unhealthy)', () {
        const error = supabase.PostgrestException(
          message: 'Service Unavailable',
          code: '503',
        );
        expect(SyncErrorClassifier.isNetworkClass(error), isTrue);
      });

      test('returns true for 5xx wrapped app.DatabaseException', () {
        const error = app.DatabaseException('ISE', code: '500');
        expect(SyncErrorClassifier.isNetworkClass(error), isTrue);
      });

      test('returns false for an all-digit SQLSTATE that parses but is not 5xx '
          '(42501 RLS denial)', () {
        // 42501 happens to int.tryParse to 42501 — but it is a Postgres
        // SQLSTATE (insufficient_privilege), NOT an HTTP status. Pin that it
        // stays OUT of the 500-599 server-class window so a future edit to
        // that range can't silently turn an all-digit SQLSTATE into a false
        // network-class / server-error-copy classification.
        const error = app.DatabaseException('RLS denied', code: '42501');
        expect(SyncErrorClassifier.httpCode(error), 42501);
        expect(SyncErrorClassifier.isNetworkClass(error), isFalse);
      });

      test(
        'returns true for raw supabase.AuthException with 401 (token refresh)',
        () {
          // Only 401 ("JWT expired" / unauthenticated) counts as transient.
          // The SDK auto-refreshes the session and the next call usually
          // succeeds — that successful retry trips the recovery signal.
          expect(
            SyncErrorClassifier.isNetworkClass(
              const supabase.AuthException('JWT expired', statusCode: '401'),
            ),
            isTrue,
          );
        },
      );

      test(
        'returns true for wrapped app.AuthException with 401 (token refresh)',
        () {
          expect(
            SyncErrorClassifier.isNetworkClass(
              const app.AuthException('JWT expired', code: '401'),
            ),
            isTrue,
          );
        },
      );

      test(
        'returns false for raw supabase.AuthException with no statusCode',
        () {
          // Pre-fix: any AuthException tripped recovery. Now: only 401.
          // An exception without a statusCode (e.g. some local SDK errors)
          // is NOT classified as network — treating it so would risk
          // arming the window on permanent domain errors that bubble up
          // without an HTTP code.
          expect(
            SyncErrorClassifier.isNetworkClass(
              const supabase.AuthException('JWT expired'),
            ),
            isFalse,
          );
        },
      );

      test('returns false for raw supabase.AuthException with 400 '
          '(invalid credentials)', () {
        // Wrong password / sign-up validation — permanent domain errors.
        // Will never self-heal; recording as network would arm the window
        // every time the user mistypes their password and false-trigger a
        // drain on the next successful call.
        expect(
          SyncErrorClassifier.isNetworkClass(
            const supabase.AuthException(
              'Invalid login credentials',
              statusCode: '400',
            ),
          ),
          isFalse,
        );
      });

      test('returns false for raw supabase.AuthException with 403 '
          '(email not confirmed)', () {
        expect(
          SyncErrorClassifier.isNetworkClass(
            const supabase.AuthException(
              'Email not confirmed',
              statusCode: '403',
            ),
          ),
          isFalse,
        );
      });

      test(
        'returns false for raw supabase.AuthException with 422 (weak password)',
        () {
          expect(
            SyncErrorClassifier.isNetworkClass(
              const supabase.AuthException(
                'Password is too weak',
                statusCode: '422',
              ),
            ),
            isFalse,
          );
        },
      );

      test(
        'returns false for raw supabase.AuthException with 429 (rate limited)',
        () {
          // Rate-limit is a domain signal — backing off via the queue's own
          // retry/backoff is correct; don't false-trip recovery on it.
          expect(
            SyncErrorClassifier.isNetworkClass(
              const supabase.AuthException(
                'Too many requests',
                statusCode: '429',
              ),
            ),
            isFalse,
          );
        },
      );

      test(
        'returns false for wrapped app.AuthException with 400 (invalid creds)',
        () {
          expect(
            SyncErrorClassifier.isNetworkClass(
              const app.AuthException('Invalid credentials', code: '400'),
            ),
            isFalse,
          );
        },
      );

      test('returns false for 400 PostgrestException (domain error)', () {
        const error = supabase.PostgrestException(
          message: 'Bad Request',
          code: '400',
        );
        expect(SyncErrorClassifier.isNetworkClass(error), isFalse);
      });

      test('returns false for 404 PostgrestException (domain error)', () {
        const error = supabase.PostgrestException(
          message: 'Not Found',
          code: '404',
        );
        expect(SyncErrorClassifier.isNetworkClass(error), isFalse);
      });

      test('returns false for 422 wrapped app.DatabaseException', () {
        const error = app.DatabaseException('Unprocessable', code: '422');
        expect(SyncErrorClassifier.isNetworkClass(error), isFalse);
      });

      test('returns false for app.ValidationException (domain error)', () {
        expect(
          SyncErrorClassifier.isNetworkClass(
            const app.ValidationException('Required', field: 'name'),
          ),
          isFalse,
        );
      });

      test(
        'returns false for unknown exception types (conservative default)',
        () {
          // Unknown shapes are not classified as network — the recovery
          // signal must be conservative and only fire on clearly-network
          // failures. An unknown exception triggering the recovery path
          // would risk false drains and retry storms.
          expect(
            SyncErrorClassifier.isNetworkClass(Exception('random')),
            isFalse,
          );
        },
      );
    });
  });
}
