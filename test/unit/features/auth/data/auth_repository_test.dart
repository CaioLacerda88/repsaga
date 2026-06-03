import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/exceptions/app_exception.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class MockGoTrueClient extends Mock implements supabase.GoTrueClient {}

class MockFunctionsClient extends Mock implements supabase.FunctionsClient {}

class FakeAuthResponse extends Fake implements supabase.AuthResponse {
  FakeAuthResponse({this.session});

  @override
  final supabase.Session? session;
}

void main() {
  late MockGoTrueClient mockAuth;
  late MockFunctionsClient mockFunctions;
  late AuthRepository repo;

  setUpAll(() {
    // Required so `any(named: 'body')` / `captureAny(named: 'body')` can
    // match the `Map<String, dynamic>` passed to `FunctionsClient.invoke`.
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockAuth = MockGoTrueClient();
    mockFunctions = MockFunctionsClient();
    repo = AuthRepository(mockAuth, functions: mockFunctions);
  });

  group('AuthRepository', () {
    group('signUpWithEmail', () {
      test('returns AuthResponse on success', () async {
        final response = FakeAuthResponse();
        when(
          () => mockAuth.signUp(email: 'a@b.com', password: '123456'),
        ).thenAnswer((_) async => response);

        final result = await repo.signUpWithEmail(
          email: 'a@b.com',
          password: '123456',
        );

        expect(result, same(response));
        verify(
          () => mockAuth.signUp(email: 'a@b.com', password: '123456'),
        ).called(1);
      });

      test('maps AuthApiException to AuthException', () async {
        when(
          () => mockAuth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenThrow(
          supabase.AuthApiException(
            'User already registered',
            statusCode: '400',
          ),
        );

        expect(
          () => repo.signUpWithEmail(email: 'a@b.com', password: '123456'),
          throwsA(
            isA<AuthException>()
                .having((e) => e.message, 'message', 'User already registered')
                .having((e) => e.code, 'code', '400'),
          ),
        );
      });

      // Locale forwarding — Round 4.5: signUpWithEmail must pass the app's
      // current locale as `data: {'locale': ...}` so Supabase stores it on
      // `user_metadata.locale`, which the email-template Go conditional reads
      // (`{{ if eq .Data.locale "pt" }}`) to route between en and pt-BR.
      test(
        'forwards locale "pt" as data: {locale: pt} on the underlying signUp',
        () async {
          when(
            () => mockAuth.signUp(
              email: 'a@b.com',
              password: '123456',
              data: {'locale': 'pt'},
            ),
          ).thenAnswer((_) async => FakeAuthResponse());

          await repo.signUpWithEmail(
            email: 'a@b.com',
            password: '123456',
            locale: 'pt',
          );

          verify(
            () => mockAuth.signUp(
              email: 'a@b.com',
              password: '123456',
              data: {'locale': 'pt'},
            ),
          ).called(1);
        },
      );

      test(
        'forwards locale "en" as data: {locale: en} on the underlying signUp',
        () async {
          when(
            () => mockAuth.signUp(
              email: 'a@b.com',
              password: '123456',
              data: {'locale': 'en'},
            ),
          ).thenAnswer((_) async => FakeAuthResponse());

          await repo.signUpWithEmail(
            email: 'a@b.com',
            password: '123456',
            locale: 'en',
          );

          verify(
            () => mockAuth.signUp(
              email: 'a@b.com',
              password: '123456',
              data: {'locale': 'en'},
            ),
          ).called(1);
        },
      );

      test(
        'omits data entirely when no locale is provided (null pass-through)',
        () async {
          when(
            () => mockAuth.signUp(email: 'a@b.com', password: '123456'),
          ).thenAnswer((_) async => FakeAuthResponse());

          await repo.signUpWithEmail(email: 'a@b.com', password: '123456');

          // Pins the null-pass-through: when no locale is supplied to the
          // repository, the underlying signUp must receive `data` at its
          // default (`null`), NOT `{'locale': null}` or an empty map. A
          // `{'locale': null}` payload would overwrite `user_metadata` on
          // the auth.users row with a null-valued key and break OAuth flows
          // that wrote metadata earlier. The verify below omits the `data:`
          // named arg, which mocktail matches only against recorded calls
          // whose `data` argument equals the parameter default (null).
          verify(
            () => mockAuth.signUp(email: 'a@b.com', password: '123456'),
          ).called(1);
        },
      );
    });

    group('signInWithEmail', () {
      test('returns AuthResponse on success', () async {
        final response = FakeAuthResponse();
        when(
          () =>
              mockAuth.signInWithPassword(email: 'a@b.com', password: '123456'),
        ).thenAnswer((_) async => response);

        final result = await repo.signInWithEmail(
          email: 'a@b.com',
          password: '123456',
        );

        expect(result, same(response));
      });

      test(
        'maps AuthApiException to AuthException on invalid credentials',
        () async {
          when(
            () => mockAuth.signInWithPassword(
              email: any(named: 'email'),
              password: any(named: 'password'),
            ),
          ).thenThrow(
            supabase.AuthApiException(
              'Invalid login credentials',
              statusCode: '401',
            ),
          );

          expect(
            () => repo.signInWithEmail(email: 'a@b.com', password: 'wrong'),
            throwsA(
              isA<AuthException>()
                  .having(
                    (e) => e.message,
                    'message',
                    'Invalid login credentials',
                  )
                  .having((e) => e.code, 'code', '401'),
            ),
          );
        },
      );
    });

    group('signOut', () {
      test('completes successfully', () async {
        when(() => mockAuth.signOut()).thenAnswer((_) async {});

        await expectLater(repo.signOut(), completes);
        verify(() => mockAuth.signOut()).called(1);
      });

      test('maps errors through mapException', () async {
        when(() => mockAuth.signOut()).thenThrow(Exception('Network error'));

        expect(() => repo.signOut(), throwsA(isA<NetworkException>()));
      });
    });

    group('refreshSession', () {
      test('returns AuthResponse on success', () async {
        final response = FakeAuthResponse();
        when(() => mockAuth.refreshSession()).thenAnswer((_) async => response);

        final result = await repo.refreshSession();

        expect(result, same(response));
      });

      test('maps AuthApiException on expired session', () async {
        when(() => mockAuth.refreshSession()).thenThrow(
          supabase.AuthApiException('Session expired', statusCode: '401'),
        );

        expect(
          () => repo.refreshSession(),
          throwsA(isA<AuthException>().having((e) => e.code, 'code', '401')),
        );
      });
    });

    group('currentSession', () {
      test('returns null when no session', () {
        when(() => mockAuth.currentSession).thenReturn(null);

        expect(repo.currentSession, isNull);
      });
    });

    group('onAuthStateChange', () {
      test('exposes the auth state stream', () {
        const stream = Stream<supabase.AuthState>.empty();
        when(() => mockAuth.onAuthStateChange).thenAnswer((_) => stream);

        expect(repo.onAuthStateChange(), same(stream));
      });
    });

    group('deleteAccount', () {
      test('invokes the delete-user Edge Function on success', () async {
        when(
          () => mockFunctions.invoke(any(), body: any(named: 'body')),
        ).thenAnswer(
          (_) async =>
              supabase.FunctionResponse(data: {'success': true}, status: 200),
        );

        await expectLater(repo.deleteAccount(), completes);
        verify(
          () => mockFunctions.invoke('delete-user', body: any(named: 'body')),
        ).called(1);
      });

      test(
        'forwards platform + app_version in the Edge Function body',
        () async {
          when(
            () => mockFunctions.invoke(any(), body: any(named: 'body')),
          ).thenAnswer(
            (_) async =>
                supabase.FunctionResponse(data: {'success': true}, status: 200),
          );

          await repo.deleteAccount(platform: 'android', appVersion: '1.2.3');

          final captured = verify(
            () => mockFunctions.invoke(
              'delete-user',
              body: captureAny(named: 'body'),
            ),
          ).captured;
          expect(captured.single, isA<Map<String, dynamic>>());
          final body = captured.single as Map<String, dynamic>;
          expect(body['platform'], 'android');
          expect(body['app_version'], '1.2.3');
        },
      );

      test('omits platform and app_version from body when both are null '
          '(collection-if must not produce null-value keys)', () async {
        // Guards the CI fix (commit 897bc89): the collection-if syntax
        // `if (x != null) 'key': x` must produce an EMPTY map when both
        // args are null — not a map with null values like
        // `{'platform': null, 'app_version': null}`, which the Edge Function
        // would receive and store in the audit row.
        when(
          () => mockFunctions.invoke(any(), body: any(named: 'body')),
        ).thenAnswer(
          (_) async =>
              supabase.FunctionResponse(data: {'success': true}, status: 200),
        );

        await repo
            .deleteAccount(); // both platform and appVersion default to null

        final captured = verify(
          () => mockFunctions.invoke(
            'delete-user',
            body: captureAny(named: 'body'),
          ),
        ).captured;
        expect(captured.single, isA<Map<String, dynamic>>());
        final body = captured.single as Map<String, dynamic>;
        expect(
          body.containsKey('platform'),
          isFalse,
          reason:
              'When platform is null the collection-if must omit the key '
              'entirely, not insert a null value.',
        );
        expect(
          body.containsKey('app_version'),
          isFalse,
          reason:
              'When appVersion is null the collection-if must omit the key '
              'entirely, not insert a null value.',
        );
      });

      test('throws when the Edge Function returns a 4xx status', () async {
        when(
          () => mockFunctions.invoke(any(), body: any(named: 'body')),
        ).thenAnswer(
          (_) async =>
              supabase.FunctionResponse(data: {'error': 'bad'}, status: 401),
        );

        expect(() => repo.deleteAccount(), throwsA(isA<AppException>()));
      });

      test('throws when the Edge Function returns a 5xx status', () async {
        when(
          () => mockFunctions.invoke(any(), body: any(named: 'body')),
        ).thenAnswer(
          (_) async =>
              supabase.FunctionResponse(data: {'error': 'oops'}, status: 500),
        );

        expect(() => repo.deleteAccount(), throwsA(isA<AppException>()));
      });

      test('maps thrown errors through mapException', () async {
        when(
          () => mockFunctions.invoke(any(), body: any(named: 'body')),
        ).thenThrow(Exception('Network down'));

        expect(() => repo.deleteAccount(), throwsA(isA<NetworkException>()));
      });
    });
  });
}
