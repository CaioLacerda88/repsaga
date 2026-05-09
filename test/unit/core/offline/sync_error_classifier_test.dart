import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/exceptions/app_exception.dart' as app;
import 'package:repsaga/core/offline/sync_error_classifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

void main() {
  group('SyncErrorClassifier', () {
    group('isTerminal', () {
      test('returns true for 400 Bad Request', () {
        const error = supabase.PostgrestException(
          message: 'Bad Request',
          code: '400',
        );
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns false for 401 Unauthorized (JWT auto-refresh)', () {
        const error = supabase.PostgrestException(
          message: 'Unauthorized',
          code: '401',
        );
        expect(SyncErrorClassifier.isTerminal(error), isFalse);
      });

      test('returns true for 403 Forbidden', () {
        const error = supabase.PostgrestException(
          message: 'Forbidden',
          code: '403',
        );
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns true for 404 Not Found', () {
        const error = supabase.PostgrestException(
          message: 'Not Found',
          code: '404',
        );
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns true for 409 Conflict', () {
        const error = supabase.PostgrestException(
          message: 'Conflict',
          code: '409',
        );
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns true for 422 Unprocessable Entity', () {
        const error = supabase.PostgrestException(
          message: 'Unprocessable',
          code: '422',
        );
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns false for 500 Internal Server Error', () {
        const error = supabase.PostgrestException(message: 'ISE', code: '500');
        expect(SyncErrorClassifier.isTerminal(error), isFalse);
      });

      test('returns false for 502 Bad Gateway', () {
        const error = supabase.PostgrestException(
          message: 'Bad Gateway',
          code: '502',
        );
        expect(SyncErrorClassifier.isTerminal(error), isFalse);
      });

      test('returns false for 503 Service Unavailable', () {
        const error = supabase.PostgrestException(
          message: 'Unavailable',
          code: '503',
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

      test('returns false for AuthException', () {
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

      test('returns false for PostgrestException with non-numeric code', () {
        const error = supabase.PostgrestException(
          message: 'Unknown',
          code: 'PGRST',
        );
        expect(SyncErrorClassifier.isTerminal(error), isFalse);
      });

      // Wrapped app.* exception types — repository layer maps raw Supabase
      // errors into these via BaseRepository.mapException. The classifier
      // must recognise both shapes (PR1B catch-site sees the wrapped form).
      test('returns true for wrapped app.DatabaseException with 400', () {
        const error = app.DatabaseException('Bad Request', code: '400');
        expect(SyncErrorClassifier.isTerminal(error), isTrue);
      });

      test('returns false for wrapped app.DatabaseException with 500', () {
        const error = app.DatabaseException('ISE', code: '500');
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

    // The httpCode helper is the single canonical extractor used by call
    // sites that want the numeric HTTP code (e.g. the active-workout notifier
    // discriminating 5xx queue copy). It must recognise exactly the same
    // code-bearing shapes that isTerminal pattern-matches; if a new wrapped
    // form is added to isTerminal, it must also be added here so the two
    // paths don't drift.
    group('httpCode', () {
      test('returns parsed code for PostgrestException with numeric code', () {
        const error = supabase.PostgrestException(
          message: 'Bad Request',
          code: '400',
        );
        expect(SyncErrorClassifier.httpCode(error), 400);
      });

      test('returns parsed code for wrapped app.DatabaseException', () {
        const error = app.DatabaseException('ISE', code: '500');
        expect(SyncErrorClassifier.httpCode(error), 500);
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
