import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/data/profile_repository.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/profile/ui/widgets/bodyweight_row.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../../helpers/test_material_app.dart';

class _MockProfileRepository extends Mock implements ProfileRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockUser extends Mock implements supabase.User {}

class _StubProfileNotifier extends AsyncNotifier<Profile?>
    with Mock
    implements ProfileNotifier {
  _StubProfileNotifier(this._profile);
  final Profile? _profile;

  @override
  Future<Profile?> build() async => _profile;
}

void main() {
  setUpAll(() {
    registerFallbackValue(const Profile(id: 'fallback'));
  });

  Widget buildHost({
    Profile? profile,
    Locale locale = const Locale('en'),
    _MockProfileRepository? repo,
    _MockAuthRepository? auth,
  }) {
    final mockRepo = repo ?? _MockProfileRepository();
    final mockAuth = auth ?? _MockAuthRepository();
    final mockUser = _MockUser();
    when(() => mockUser.id).thenReturn('user-1');
    when(() => mockAuth.currentUser).thenReturn(mockUser);

    return ProviderScope(
      overrides: [
        profileProvider.overrideWith(() => _StubProfileNotifier(profile)),
        profileRepositoryProvider.overrideWithValue(mockRepo),
        authRepositoryProvider.overrideWithValue(mockAuth),
      ],
      child: TestMaterialApp(
        theme: AppTheme.dark,
        locale: locale,
        home: Scaffold(body: BodyweightRow(profile: profile)),
      ),
    );
  }

  group('BodyweightRow', () {
    testWidgets(
      'renders "Not set" subtitle when profile.bodyweightKg is null',
      (tester) async {
        const profile = Profile(id: 'user-1', weightUnit: 'kg');

        await tester.pumpWidget(buildHost(profile: profile));
        await tester.pump();

        expect(find.text('Body weight'), findsOneWidget);
        expect(find.text('Not set'), findsOneWidget);
      },
    );

    testWidgets(
      'renders "70.5 kg" with dot decimal in en locale when bodyweight is set',
      (tester) async {
        const profile = Profile(
          id: 'user-1',
          weightUnit: 'kg',
          bodyweightKg: 70.5,
        );

        await tester.pumpWidget(buildHost(profile: profile));
        await tester.pump();

        expect(find.text('70.5 kg'), findsOneWidget);
      },
    );

    testWidgets(
      'renders "70,5 kg" with comma decimal in pt locale when bodyweight is set',
      (tester) async {
        const profile = Profile(
          id: 'user-1',
          weightUnit: 'kg',
          bodyweightKg: 70.5,
        );

        await tester.pumpWidget(
          buildHost(profile: profile, locale: const Locale('pt')),
        );
        await tester.pump();

        expect(find.text('70,5 kg'), findsOneWidget);
      },
    );

    testWidgets(
      'renders integer kg without trailing decimal (80 kg, not 80.0 kg)',
      (tester) async {
        const profile = Profile(
          id: 'user-1',
          weightUnit: 'kg',
          bodyweightKg: 80,
        );

        await tester.pumpWidget(buildHost(profile: profile));
        await tester.pump();

        expect(find.text('80 kg'), findsOneWidget);
      },
    );

    testWidgets(
      'displays bodyweight converted to lbs when profile.weightUnit is lbs',
      (tester) async {
        // 70 kg => ~154.3 lbs (rendered with one decimal place).
        const profile = Profile(
          id: 'user-1',
          weightUnit: 'lbs',
          bodyweightKg: 70,
        );

        await tester.pumpWidget(buildHost(profile: profile));
        await tester.pump();

        // Stored kg=70 -> 70 * 2.20462 = 154.3234 -> formatted "154.3 lbs".
        expect(find.text('154.3 lbs'), findsOneWidget);
      },
    );

    testWidgets('tapping the row opens the bodyweight bottom sheet', (
      tester,
    ) async {
      const profile = Profile(id: 'user-1', weightUnit: 'kg');

      await tester.pumpWidget(buildHost(profile: profile));
      await tester.pump();

      await tester.tap(find.text('Body weight'));
      await tester.pumpAndSettle();

      // Helper text is unique to the sheet (the row only shows label + value).
      expect(
        find.text(
          'Used to compute XP for bodyweight exercises like pull-ups, '
          'dips, push-ups.',
        ),
        findsOneWidget,
      );
      expect(find.byType(BodyweightEditorSheet), findsOneWidget);
    });
  });

  group('BodyweightEditorSheet', () {
    testWidgets('pre-fills the input with the current bodyweight in kg', (
      tester,
    ) async {
      const profile = Profile(
        id: 'user-1',
        weightUnit: 'kg',
        bodyweightKg: 72.5,
      );

      await tester.pumpWidget(buildHost(profile: profile));
      await tester.pump();
      await tester.tap(find.text('Body weight'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(BodyweightEditorSheet),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller?.text, '72.5');
    });

    testWidgets(
      'pre-fills the input with the lbs-converted value when weightUnit is lbs',
      (tester) async {
        const profile = Profile(
          id: 'user-1',
          weightUnit: 'lbs',
          bodyweightKg: 70,
        );

        await tester.pumpWidget(buildHost(profile: profile));
        await tester.pump();
        await tester.tap(find.text('Body weight'));
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(
          find.descendant(
            of: find.byType(BodyweightEditorSheet),
            matching: find.byType(TextField),
          ),
        );
        // 70 kg * 2.20462 = 154.3234 -> toStringAsFixed(1) -> "154.3"
        expect(field.controller?.text, '154.3');
      },
    );

    testWidgets('saving a valid kg value calls upsertProfile with that kg', (
      tester,
    ) async {
      final mockRepo = _MockProfileRepository();
      when(
        () => mockRepo.upsertProfile(
          userId: any(named: 'userId'),
          bodyweightKg: any(named: 'bodyweightKg'),
        ),
      ).thenAnswer(
        (_) async =>
            const Profile(id: 'user-1', weightUnit: 'kg', bodyweightKg: 75),
      );

      const profile = Profile(id: 'user-1', weightUnit: 'kg');

      await tester.pumpWidget(buildHost(profile: profile, repo: mockRepo));
      await tester.pump();
      await tester.tap(find.text('Body weight'));
      await tester.pumpAndSettle();

      // Replace the empty input with a valid value.
      await tester.enterText(find.byType(TextField), '75');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      verify(
        () => mockRepo.upsertProfile(userId: 'user-1', bodyweightKg: 75),
      ).called(1);

      // Sheet dismisses after a successful save.
      expect(find.byType(BodyweightEditorSheet), findsNothing);
    });

    testWidgets(
      'saving a value entered in lbs converts to kg before calling upsertProfile',
      (tester) async {
        final mockRepo = _MockProfileRepository();
        when(
          () => mockRepo.upsertProfile(
            userId: any(named: 'userId'),
            bodyweightKg: any(named: 'bodyweightKg'),
          ),
        ).thenAnswer(
          (_) async =>
              const Profile(id: 'user-1', weightUnit: 'lbs', bodyweightKg: 70),
        );

        const profile = Profile(id: 'user-1', weightUnit: 'lbs');

        await tester.pumpWidget(buildHost(profile: profile, repo: mockRepo));
        await tester.pump();
        await tester.tap(find.text('Body weight'));
        await tester.pumpAndSettle();

        // 154.3234 lbs -> 70 kg (within float tolerance).
        await tester.enterText(find.byType(TextField), '154.3234');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final captured =
            verify(
                  () => mockRepo.upsertProfile(
                    userId: 'user-1',
                    bodyweightKg: captureAny(named: 'bodyweightKg'),
                  ),
                ).captured.single
                as double;
        expect(captured, closeTo(70, 1e-3));
      },
    );

    testWidgets(
      'saving a pt-formatted value (comma decimal) parses correctly',
      (tester) async {
        final mockRepo = _MockProfileRepository();
        when(
          () => mockRepo.upsertProfile(
            userId: any(named: 'userId'),
            bodyweightKg: any(named: 'bodyweightKg'),
          ),
        ).thenAnswer(
          (_) async =>
              const Profile(id: 'user-1', weightUnit: 'kg', bodyweightKg: 80.5),
        );

        const profile = Profile(id: 'user-1', weightUnit: 'kg');

        await tester.pumpWidget(
          buildHost(
            profile: profile,
            repo: mockRepo,
            locale: const Locale('pt'),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('Peso corporal'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '80,5');
        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();

        verify(
          () => mockRepo.upsertProfile(userId: 'user-1', bodyweightKg: 80.5),
        ).called(1);
      },
    );

    testWidgets(
      'out-of-range value (below 25 kg) shows validation error and does NOT call upsert',
      (tester) async {
        final mockRepo = _MockProfileRepository();
        const profile = Profile(id: 'user-1', weightUnit: 'kg');

        await tester.pumpWidget(buildHost(profile: profile, repo: mockRepo));
        await tester.pump();
        await tester.tap(find.text('Body weight'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '24');
        await tester.tap(find.text('Save'));
        await tester.pump();

        expect(
          find.text('Enter a value between 25 and 250 kg'),
          findsOneWidget,
        );
        verifyNever(
          () => mockRepo.upsertProfile(
            userId: any(named: 'userId'),
            bodyweightKg: any(named: 'bodyweightKg'),
          ),
        );
        // Sheet stays open so the user can correct.
        expect(find.byType(BodyweightEditorSheet), findsOneWidget);
      },
    );

    testWidgets(
      'out-of-range value (above 250 kg) shows validation error and does NOT call upsert',
      (tester) async {
        final mockRepo = _MockProfileRepository();
        const profile = Profile(id: 'user-1', weightUnit: 'kg');

        await tester.pumpWidget(buildHost(profile: profile, repo: mockRepo));
        await tester.pump();
        await tester.tap(find.text('Body weight'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '251');
        await tester.tap(find.text('Save'));
        await tester.pump();

        expect(
          find.text('Enter a value between 25 and 250 kg'),
          findsOneWidget,
        );
        verifyNever(
          () => mockRepo.upsertProfile(
            userId: any(named: 'userId'),
            bodyweightKg: any(named: 'bodyweightKg'),
          ),
        );
      },
    );

    testWidgets('empty input shows validation error and does NOT call upsert', (
      tester,
    ) async {
      final mockRepo = _MockProfileRepository();
      const profile = Profile(id: 'user-1', weightUnit: 'kg');

      await tester.pumpWidget(buildHost(profile: profile, repo: mockRepo));
      await tester.pump();
      await tester.tap(find.text('Body weight'));
      await tester.pumpAndSettle();

      // Input starts empty (no prior bodyweight); tap Save.
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Enter a value between 25 and 250 kg'), findsOneWidget);
      verifyNever(
        () => mockRepo.upsertProfile(
          userId: any(named: 'userId'),
          bodyweightKg: any(named: 'bodyweightKg'),
        ),
      );
    });

    testWidgets(
      'helper text shows the lbs range when profile.weightUnit is lbs',
      (tester) async {
        final mockRepo = _MockProfileRepository();
        const profile = Profile(id: 'user-1', weightUnit: 'lbs');

        await tester.pumpWidget(buildHost(profile: profile, repo: mockRepo));
        await tester.pump();
        await tester.tap(find.text('Body weight'));
        await tester.pumpAndSettle();

        // Trigger validation with an empty input to surface the error message
        // formatted with the lbs-equivalent bounds (55–551 lbs).
        await tester.tap(find.text('Save'));
        await tester.pump();

        // 25 kg -> 55.1155 lbs -> rounded 55. 250 kg -> 551.155 lbs -> 551.
        expect(
          find.text('Enter a value between 55 and 551 lbs'),
          findsOneWidget,
        );
      },
    );

    testWidgets('cancel dismisses the sheet without calling upsertProfile', (
      tester,
    ) async {
      final mockRepo = _MockProfileRepository();
      const profile = Profile(id: 'user-1', weightUnit: 'kg', bodyweightKg: 70);

      await tester.pumpWidget(buildHost(profile: profile, repo: mockRepo));
      await tester.pump();
      await tester.tap(find.text('Body weight'));
      await tester.pumpAndSettle();

      // Type a different value but cancel instead of save.
      await tester.enterText(find.byType(TextField), '99');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(
        () => mockRepo.upsertProfile(
          userId: any(named: 'userId'),
          bodyweightKg: any(named: 'bodyweightKg'),
        ),
      );
      expect(find.byType(BodyweightEditorSheet), findsNothing);
    });

    testWidgets(
      'typing into the field clears a previously-shown validation error',
      (tester) async {
        final mockRepo = _MockProfileRepository();
        const profile = Profile(id: 'user-1', weightUnit: 'kg');

        await tester.pumpWidget(buildHost(profile: profile, repo: mockRepo));
        await tester.pump();
        await tester.tap(find.text('Body weight'));
        await tester.pumpAndSettle();

        // Trigger validation error.
        await tester.tap(find.text('Save'));
        await tester.pump();
        expect(
          find.text('Enter a value between 25 and 250 kg'),
          findsOneWidget,
        );

        // User starts typing a corrected value — error should disappear.
        await tester.enterText(find.byType(TextField), '7');
        await tester.pump();
        expect(find.text('Enter a value between 25 and 250 kg'), findsNothing);
      },
    );
  });
}
