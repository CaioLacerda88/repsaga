import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/exceptions/app_exception.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/personal_records/data/pr_repository.dart';
import 'package:repsaga/features/personal_records/providers/pr_providers.dart';
import 'package:repsaga/features/profile/ui/manage_data_screen.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/shared/widgets/gradient_button.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../helpers/test_material_app.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockAuthRepository extends Mock implements AuthRepository {}

class MockUser extends Mock implements User {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockPRRepository extends Mock implements PRRepository {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget buildTestWidget({
  int workoutCount = 14,
  int prCount = 3,
  MockWorkoutRepository? workoutRepo,
  MockPRRepository? prRepo,
  MockAuthRepository? authRepo,
}) {
  final mockAuth = authRepo ?? MockAuthRepository();
  final mockUser = MockUser();
  when(() => mockUser.id).thenReturn('user-001');
  when(() => mockAuth.currentUser).thenReturn(mockUser);
  when(() => mockAuth.currentSession).thenReturn(null);
  when(
    () => mockAuth.onAuthStateChange(),
  ).thenAnswer((_) => const Stream<AuthState>.empty());
  if (authRepo == null) {
    when(
      () => mockAuth.deleteAccount(
        platform: any(named: 'platform'),
        appVersion: any(named: 'appVersion'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockAuth.signOut()).thenAnswer((_) async {});
  }

  final mockWorkoutRepo = workoutRepo ?? MockWorkoutRepository();
  if (workoutRepo == null) {
    when(
      () => mockWorkoutRepo.clearHistory(
        any(),
        includeActive: any(named: 'includeActive'),
      ),
    ).thenAnswer((_) async {});
  }

  final mockPRRepo = prRepo ?? MockPRRepository();
  if (prRepo == null) {
    when(() => mockPRRepo.clearAllRecords(any())).thenAnswer((_) async {});
  }

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(mockAuth),
      workoutRepositoryProvider.overrideWithValue(mockWorkoutRepo),
      prRepositoryProvider.overrideWithValue(mockPRRepo),
      workoutCountProvider.overrideWith((ref) => Future.value(workoutCount)),
      prCountProvider.overrideWith((ref) => Future.value(prCount)),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: const ManageDataScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ManageDataScreen', () {
    testWidgets('renders all data management options', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      await tester.pump();

      expect(find.text('WORKOUT HISTORY'), findsOneWidget);
      expect(find.text('Delete Workout History'), findsOneWidget);
      expect(find.text('DANGER'), findsOneWidget);
      expect(find.text('Reset All Account Data'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);
      expect(
        find.text('Permanently delete your account and all data'),
        findsOneWidget,
      );
    });

    testWidgets('shows live workout count in subtitle', (tester) async {
      await tester.pumpWidget(buildTestWidget(workoutCount: 14));
      await tester.pump();
      await tester.pump();

      expect(find.text('14 workouts will be removed'), findsOneWidget);
    });

    testWidgets('shows 0 workouts in subtitle when none exist', (tester) async {
      await tester.pumpWidget(buildTestWidget(workoutCount: 0));
      await tester.pump();
      await tester.pump();

      expect(find.text('0 workouts will be removed'), findsOneWidget);
    });

    group('Delete Workout History two-step dialog', () {
      testWidgets('first dialog shows count and delete button', (tester) async {
        await tester.pumpWidget(buildTestWidget(workoutCount: 14));
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Delete Workout History'));
        await tester.pumpAndSettle();

        expect(find.text('Delete all workout history?'), findsOneWidget);
        expect(
          find.textContaining('permanently delete all 14 workouts'),
          findsOneWidget,
        );
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Delete History'), findsOneWidget);
      });

      testWidgets('cancel at first step aborts', (tester) async {
        final mockWorkoutRepo = MockWorkoutRepository();
        when(
          () => mockWorkoutRepo.clearHistory(any()),
        ).thenAnswer((_) async {});

        await tester.pumpWidget(buildTestWidget(workoutRepo: mockWorkoutRepo));
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Delete Workout History'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        verifyNever(() => mockWorkoutRepo.clearHistory(any()));
      });

      testWidgets('second dialog asks for confirmation', (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Delete Workout History'));
        await tester.pumpAndSettle();

        // Proceed past first dialog.
        await tester.tap(find.text('Delete History'));
        await tester.pumpAndSettle();

        expect(find.text('Are you sure?'), findsOneWidget);
        expect(
          find.text('Your personal records and routines will be kept.'),
          findsOneWidget,
        );
        expect(find.text('Yes, Delete'), findsOneWidget);
      });

      testWidgets('cancel at second step aborts', (tester) async {
        final mockWorkoutRepo = MockWorkoutRepository();
        when(
          () => mockWorkoutRepo.clearHistory(any()),
        ).thenAnswer((_) async {});

        await tester.pumpWidget(buildTestWidget(workoutRepo: mockWorkoutRepo));
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Delete Workout History'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete History'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        verifyNever(() => mockWorkoutRepo.clearHistory(any()));
      });

      testWidgets('confirm at second step triggers delete and shows snackbar', (
        tester,
      ) async {
        final mockWorkoutRepo = MockWorkoutRepository();
        when(
          () => mockWorkoutRepo.clearHistory(any()),
        ).thenAnswer((_) async {});

        await tester.pumpWidget(buildTestWidget(workoutRepo: mockWorkoutRepo));
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Delete Workout History'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete History'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Yes, Delete'));
        await tester.pumpAndSettle();

        verify(() => mockWorkoutRepo.clearHistory('user-001')).called(1);
        expect(find.text('Workout history cleared'), findsOneWidget);
      });
    });

    group('Reset All Account Data type-to-confirm', () {
      testWidgets('shows full-screen dialog with explanation', (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Reset All Account Data'));
        await tester.pumpAndSettle();

        expect(find.text('Reset Account Data'), findsOneWidget);
        expect(
          find.textContaining('permanently delete all workouts'),
          findsOneWidget,
        );
        expect(find.text('Type RESET to confirm'), findsOneWidget);
      });

      testWidgets('Reset Account button is disabled until RESET typed', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Reset All Account Data'));
        await tester.pumpAndSettle();

        // Button should be disabled (GradientButton onPressed is null).
        final button = tester.widget<GradientButton>(
          find.byType(GradientButton),
        );
        expect(button.onPressed, isNull);

        // Type 'RESET'.
        await tester.enterText(find.byType(TextField), 'RESET');
        await tester.pump();

        // Button should now be enabled.
        final updatedButton = tester.widget<GradientButton>(
          find.byType(GradientButton),
        );
        expect(updatedButton.onPressed, isNotNull);
      });

      testWidgets('typing reset (lowercase) also enables button', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Reset All Account Data'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'reset');
        await tester.pump();

        final button = tester.widget<GradientButton>(
          find.byType(GradientButton),
        );
        expect(button.onPressed, isNotNull);
      });

      testWidgets('cancel closes dialog without deleting', (tester) async {
        final mockWorkoutRepo = MockWorkoutRepository();
        when(
          () => mockWorkoutRepo.clearHistory(
            any(),
            includeActive: any(named: 'includeActive'),
          ),
        ).thenAnswer((_) async {});
        final mockPRRepo = MockPRRepository();
        when(() => mockPRRepo.clearAllRecords(any())).thenAnswer((_) async {});

        await tester.pumpWidget(
          buildTestWidget(workoutRepo: mockWorkoutRepo, prRepo: mockPRRepo),
        );
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Reset All Account Data'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        verifyNever(
          () => mockWorkoutRepo.clearHistory(
            any(),
            includeActive: any(named: 'includeActive'),
          ),
        );
        verifyNever(() => mockPRRepo.clearAllRecords(any()));
      });

      testWidgets('confirm triggers reset and shows snackbar', (tester) async {
        final mockWorkoutRepo = MockWorkoutRepository();
        when(
          () => mockWorkoutRepo.clearHistory(
            any(),
            includeActive: any(named: 'includeActive'),
          ),
        ).thenAnswer((_) async {});
        final mockPRRepo = MockPRRepository();
        when(() => mockPRRepo.clearAllRecords(any())).thenAnswer((_) async {});

        await tester.pumpWidget(
          buildTestWidget(workoutRepo: mockWorkoutRepo, prRepo: mockPRRepo),
        );
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Reset All Account Data'));
        await tester.pumpAndSettle();

        // Type RESET and confirm.
        await tester.enterText(find.byType(TextField), 'RESET');
        await tester.pump();

        // Tap the Reset Account button (inside GradientButton).
        await tester.tap(find.text('Reset Account'));
        await tester.pumpAndSettle();

        // Cluster: data-protection-compliance. Reset All MUST pass
        // `includeActive: true` so draft / in-progress workouts are
        // wiped alongside finished history — the user-facing "ALL
        // account data" label demands it. A literal-true matcher here
        // (not `any(named: ...)`) pins the contract: if a future
        // refactor accidentally drops the named arg or flips it to
        // false, the verify fails.
        verify(
          () => mockWorkoutRepo.clearHistory('user-001', includeActive: true),
        ).called(1);
        verify(() => mockPRRepo.clearAllRecords('user-001')).called(1);
        expect(find.text('Account data reset'), findsOneWidget);
      });

      testWidgets('reset deletes PRs before workouts (FK order)', (
        tester,
      ) async {
        final callOrder = <String>[];
        final mockWorkoutRepo = MockWorkoutRepository();
        when(
          () => mockWorkoutRepo.clearHistory(
            any(),
            includeActive: any(named: 'includeActive'),
          ),
        ).thenAnswer((_) async {
          callOrder.add('clearHistory');
        });
        final mockPRRepo = MockPRRepository();
        when(() => mockPRRepo.clearAllRecords(any())).thenAnswer((_) async {
          callOrder.add('clearAllRecords');
        });

        await tester.pumpWidget(
          buildTestWidget(workoutRepo: mockWorkoutRepo, prRepo: mockPRRepo),
        );
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Reset All Account Data'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'RESET');
        await tester.pump();

        await tester.tap(find.text('Reset Account'));
        await tester.pumpAndSettle();

        // PRs must be deleted first to avoid FK violation on set_id.
        expect(callOrder, ['clearAllRecords', 'clearHistory']);
      });
    });

    group('Delete Account type-to-confirm', () {
      testWidgets('shows full-screen dialog with explanation', (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Delete Account'));
        await tester.pumpAndSettle();

        // AppBar title.
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Delete Account'),
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('permanently delete your account'),
          findsOneWidget,
        );
        expect(find.text('Type DELETE to confirm'), findsOneWidget);
      });

      testWidgets('Delete Account button is disabled until DELETE typed', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Delete Account'));
        await tester.pumpAndSettle();

        // Button should be disabled before typing.
        final button = tester.widget<GradientButton>(
          find.byType(GradientButton),
        );
        expect(button.onPressed, isNull);

        // Type 'DELETE'.
        await tester.enterText(find.byType(TextField), 'DELETE');
        await tester.pump();

        // Button should now be enabled.
        final updatedButton = tester.widget<GradientButton>(
          find.byType(GradientButton),
        );
        expect(updatedButton.onPressed, isNotNull);
      });

      testWidgets('typing delete (lowercase) also enables button', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Delete Account'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'delete');
        await tester.pump();

        final button = tester.widget<GradientButton>(
          find.byType(GradientButton),
        );
        expect(button.onPressed, isNotNull);
      });

      testWidgets(
        'DELETE confirm button stays disabled when user types "DELET" '
        '(one char short)',
        (tester) async {
          final mockAuth = MockAuthRepository();
          when(
            () => mockAuth.deleteAccount(
              platform: any(named: 'platform'),
              appVersion: any(named: 'appVersion'),
            ),
          ).thenAnswer((_) async {});
          when(() => mockAuth.signOut()).thenAnswer((_) async {});

          await tester.pumpWidget(buildTestWidget(authRepo: mockAuth));
          await tester.pump();
          await tester.pump();

          await tester.tap(find.text('Delete Account'));
          await tester.pumpAndSettle();

          // Button starts disabled.
          final initialButton = tester.widget<GradientButton>(
            find.byType(GradientButton),
          );
          expect(initialButton.onPressed, isNull);

          // Type a partial match — one char short.
          await tester.enterText(find.byType(TextField), 'DELET');
          await tester.pump();

          // Button must remain disabled.
          final button = tester.widget<GradientButton>(
            find.byType(GradientButton),
          );
          expect(button.onPressed, isNull);

          // And deleteAccount must not have been invoked.
          verifyNever(
            () => mockAuth.deleteAccount(
              platform: any(named: 'platform'),
              appVersion: any(named: 'appVersion'),
            ),
          );
        },
      );

      testWidgets(
        'DELETE confirm button stays disabled when user types "DELETED" '
        '(trailing char)',
        (tester) async {
          final mockAuth = MockAuthRepository();
          when(
            () => mockAuth.deleteAccount(
              platform: any(named: 'platform'),
              appVersion: any(named: 'appVersion'),
            ),
          ).thenAnswer((_) async {});
          when(() => mockAuth.signOut()).thenAnswer((_) async {});

          await tester.pumpWidget(buildTestWidget(authRepo: mockAuth));
          await tester.pump();
          await tester.pump();

          await tester.tap(find.text('Delete Account'));
          await tester.pumpAndSettle();

          // Button starts disabled.
          final initialButton = tester.widget<GradientButton>(
            find.byType(GradientButton),
          );
          expect(initialButton.onPressed, isNull);

          // Type a superset — one char too many.
          await tester.enterText(find.byType(TextField), 'DELETED');
          await tester.pump();

          // Button must remain disabled.
          final button = tester.widget<GradientButton>(
            find.byType(GradientButton),
          );
          expect(button.onPressed, isNull);

          // And deleteAccount must not have been invoked.
          verifyNever(
            () => mockAuth.deleteAccount(
              platform: any(named: 'platform'),
              appVersion: any(named: 'appVersion'),
            ),
          );
        },
      );

      testWidgets('cancel closes dialog without invoking deleteAccount', (
        tester,
      ) async {
        final mockAuth = MockAuthRepository();
        when(
          () => mockAuth.deleteAccount(
            platform: any(named: 'platform'),
            appVersion: any(named: 'appVersion'),
          ),
        ).thenAnswer((_) async {});
        when(() => mockAuth.signOut()).thenAnswer((_) async {});

        await tester.pumpWidget(buildTestWidget(authRepo: mockAuth));
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Delete Account'));
        await tester.pumpAndSettle();

        // Two "Cancel" buttons exist (TextButton in the dialog and the
        // close icon's tooltip — only the dialog one is a TextButton).
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        verifyNever(
          () => mockAuth.deleteAccount(
            platform: any(named: 'platform'),
            appVersion: any(named: 'appVersion'),
          ),
        );
        verifyNever(() => mockAuth.signOut());
      });

      testWidgets('confirm triggers deleteAccount + signOut on the auth repo', (
        tester,
      ) async {
        final mockAuth = MockAuthRepository();
        when(
          () => mockAuth.deleteAccount(
            platform: any(named: 'platform'),
            appVersion: any(named: 'appVersion'),
          ),
        ).thenAnswer((_) async {});
        when(() => mockAuth.signOut()).thenAnswer((_) async {});

        await tester.pumpWidget(buildTestWidget(authRepo: mockAuth));
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Delete Account'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'DELETE');
        await tester.pump();

        // Tap the GradientButton labelled "Delete Account" inside the dialog.
        await tester.tap(find.byType(GradientButton));
        await tester.pumpAndSettle();

        // deleteAccount must be called before signOut — if the order were
        // reversed and signOut failed, we'd delete the account then leave
        // the user logged in (or vice versa). Order matters for UX safety.
        verifyInOrder([
          () => mockAuth.deleteAccount(
            platform: any(named: 'platform'),
            appVersion: any(named: 'appVersion'),
          ),
          () => mockAuth.signOut(),
        ]);
      });

      testWidgets(
        'shows safe error snackbar when deleteAccount throws AppException',
        (tester) async {
          final mockAuth = MockAuthRepository();
          when(
            () => mockAuth.deleteAccount(
              platform: any(named: 'platform'),
              appVersion: any(named: 'appVersion'),
            ),
          ).thenThrow(const NetworkException('connection refused'));
          when(() => mockAuth.signOut()).thenAnswer((_) async {});

          await tester.pumpWidget(buildTestWidget(authRepo: mockAuth));
          await tester.pump();
          await tester.pump();

          await tester.tap(find.text('Delete Account'));
          await tester.pumpAndSettle();

          await tester.enterText(find.byType(TextField), 'DELETE');
          await tester.pump();

          await tester.tap(find.byType(GradientButton));
          await tester.pumpAndSettle();

          // Should show safe message via userMessage, not raw error.
          expect(
            find.textContaining('Failed to delete account'),
            findsOneWidget,
          );
          expect(find.textContaining('connection refused'), findsNothing);
          // signOut must NOT be called when delete fails.
          verifyNever(() => mockAuth.signOut());
        },
      );
    });

    group('Error states show safe messages', () {
      testWidgets('delete history error shows safe message, not raw DB error', (
        tester,
      ) async {
        final mockWorkoutRepo = MockWorkoutRepository();
        when(() => mockWorkoutRepo.clearHistory(any())).thenThrow(
          const DatabaseException(
            'update or delete on table "sets" violates foreign key '
            'constraint "personal_records_set_id_fkey" on table '
            '"personal_records"',
            code: '23503',
          ),
        );

        await tester.pumpWidget(buildTestWidget(workoutRepo: mockWorkoutRepo));
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Delete Workout History'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete History'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Yes, Delete'));
        await tester.pumpAndSettle();

        // Should show safe message, not raw DB error.
        expect(find.textContaining('Something went wrong'), findsOneWidget);
        // Must NOT show table names.
        expect(find.textContaining('sets'), findsNothing);
        expect(find.textContaining('personal_records'), findsNothing);
        expect(find.textContaining('foreign key'), findsNothing);
      });

      testWidgets('reset all error shows safe message, not raw DB error', (
        tester,
      ) async {
        final mockPRRepo = MockPRRepository();
        when(() => mockPRRepo.clearAllRecords(any())).thenThrow(
          const DatabaseException(
            'relation "personal_records" does not exist',
            code: '42P01',
          ),
        );

        await tester.pumpWidget(buildTestWidget(prRepo: mockPRRepo));
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Reset All Account Data'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'RESET');
        await tester.pump();

        await tester.tap(find.text('Reset Account'));
        await tester.pumpAndSettle();

        // Should show safe message.
        expect(find.textContaining('Something went wrong'), findsOneWidget);
        // Must NOT show table names.
        expect(find.textContaining('personal_records'), findsNothing);
      });
    });
  });
}
