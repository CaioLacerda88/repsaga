import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/data/profile_repository.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/gender_consent_provider.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/profile/ui/widgets/gender_row.dart';
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

/// In-memory stub for the gender-consent notifier. Sidesteps Hive disk
/// I/O (the Hive contract is unit-tested at
/// `test/unit/features/profile/providers/gender_consent_provider_test.dart`).
class _StubConsent extends Notifier<bool>
    with Mock
    implements GenderConsentNotifier {
  _StubConsent(this._initial);
  final bool _initial;

  @override
  bool build() => _initial;

  @override
  Future<void> setEnabled(bool value) async {
    state = value;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(const Profile(id: 'fallback'));
    registerFallbackValue(Gender.male);
  });

  Widget buildHost({
    Profile? profile,
    _MockProfileRepository? repo,
    _MockAuthRepository? auth,
    bool initialConsent = false,
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
        genderConsentProvider.overrideWith(() => _StubConsent(initialConsent)),
      ],
      child: TestMaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: GenderRow(profile: profile)),
      ),
    );
  }

  testWidgets('renders "Not set" subtitle when profile.gender is null', (
    tester,
  ) async {
    const profile = Profile(id: 'user-1');

    await tester.pumpWidget(buildHost(profile: profile));
    await tester.pump();

    expect(find.text('Gender'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget);
  });

  testWidgets('renders "Male" subtitle when profile.gender is male', (
    tester,
  ) async {
    const profile = Profile(id: 'user-1', gender: Gender.male);

    await tester.pumpWidget(buildHost(profile: profile));
    await tester.pump();

    expect(find.text('Male'), findsOneWidget);
  });

  testWidgets(
    'tapping the row opens the gender editor sheet with disclosure banner on first open',
    (tester) async {
      const profile = Profile(id: 'user-1');

      await tester.pumpWidget(buildHost(profile: profile));
      await tester.pump();

      await tester.tap(find.text('Gender'));
      await tester.pumpAndSettle();

      // Banner is on screen.
      expect(
        find.textContaining('Gender helps RepSaga match XP calculations'),
        findsOneWidget,
      );
      // All four options visible.
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.byType(GenderEditorSheet), findsOneWidget);
    },
  );

  testWidgets('selecting Male calls upsertProfile with Gender.male', (
    tester,
  ) async {
    final mockRepo = _MockProfileRepository();
    when(
      () => mockRepo.upsertProfile(
        userId: any(named: 'userId'),
        gender: any(named: 'gender'),
      ),
    ).thenAnswer((_) async => const Profile(id: 'user-1', gender: Gender.male));

    const profile = Profile(id: 'user-1');

    await tester.pumpWidget(buildHost(profile: profile, repo: mockRepo));
    await tester.pump();

    await tester.tap(find.text('Gender'));
    await tester.pumpAndSettle();

    // Pick the Male tile inside the sheet (not the row's label).
    await tester.tap(
      find.descendant(
        of: find.byType(GenderEditorSheet),
        matching: find.text('Male'),
      ),
    );
    await tester.pumpAndSettle();

    verify(
      () => mockRepo.upsertProfile(userId: 'user-1', gender: Gender.male),
    ).called(1);

    // Sheet dismisses.
    expect(find.byType(GenderEditorSheet), findsNothing);
  });

  testWidgets(
    'banner does NOT appear on subsequent opens once consent is recorded',
    (tester) async {
      const profile = Profile(id: 'user-1');

      await tester.pumpWidget(
        buildHost(profile: profile, initialConsent: true),
      );
      await tester.pump();

      await tester.tap(find.text('Gender'));
      await tester.pumpAndSettle();

      // Sheet open, banner NOT present.
      expect(find.byType(GenderEditorSheet), findsOneWidget);
      expect(
        find.textContaining('Gender helps RepSaga match XP calculations'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'banner does NOT appear when profile.gender is already set (consent implied by stored value)',
    (tester) async {
      // No consent flag, but profile carries a value -> still no banner
      // (user picked a value, so the disclosure is moot).
      const profile = Profile(id: 'user-1', gender: Gender.female);

      await tester.pumpWidget(buildHost(profile: profile));
      await tester.pump();

      await tester.tap(find.text('Gender'));
      await tester.pumpAndSettle();

      expect(find.byType(GenderEditorSheet), findsOneWidget);
      expect(
        find.textContaining('Gender helps RepSaga match XP calculations'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'picking "Not set" after seeing the banner self-extinguishes it on reopen (PR #309 review I1)',
    (tester) async {
      // Repro of PR #309 review I1: user opens the editor with gender ==
      // null + consent == false → banner visible. They make the
      // affirmative decision to decline by tapping "Not set". On
      // reopening the editor with the SAME state (gender still null,
      // since "Not set" doesn't write a value), the banner must NOT
      // re-appear — the user already saw the disclosure and made a
      // disclosed choice. Without the fix, the banner re-fires forever.
      final mockRepo = _MockProfileRepository();
      when(
        () => mockRepo.upsertProfile(
          userId: any(named: 'userId'),
          gender: any(named: 'gender'),
        ),
      ).thenAnswer((_) async => const Profile(id: 'user-1'));

      const profile = Profile(id: 'user-1');

      await tester.pumpWidget(buildHost(profile: profile, repo: mockRepo));
      await tester.pump();

      // First open — banner visible.
      await tester.tap(find.text('Gender'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Gender helps RepSaga match XP calculations'),
        findsOneWidget,
      );

      // Tap "Not set" inside the sheet — affirmative skip-decision.
      await tester.tap(
        find.descendant(
          of: find.byType(GenderEditorSheet),
          matching: find.text('Not set'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GenderEditorSheet), findsNothing);

      // Re-open the editor — banner must NOT re-appear.
      await tester.tap(find.text('Gender'));
      await tester.pumpAndSettle();
      expect(find.byType(GenderEditorSheet), findsOneWidget);
      expect(
        find.textContaining('Gender helps RepSaga match XP calculations'),
        findsNothing,
        reason:
            'Banner must self-extinguish after the user affirmatively '
            'picks "Not set" — re-firing it indefinitely defeats the '
            'one-time-disclosure contract.',
      );
    },
  );
}
