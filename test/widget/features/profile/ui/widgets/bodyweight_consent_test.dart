import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/data/profile_repository.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/bodyweight_consent_provider.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/profile/ui/widgets/bodyweight_consent_toggle.dart';
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

/// In-memory stub for the consent notifier. Sidesteps Hive disk I/O
/// (the Hive contract is unit-tested at
/// `test/unit/features/profile/providers/bodyweight_consent_provider_test.dart`).
class _StubConsent extends Notifier<bool>
    with Mock
    implements BodyweightConsentNotifier {
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
  });

  Widget buildEditorHost({
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
        bodyweightConsentProvider.overrideWith(
          () => _StubConsent(initialConsent),
        ),
      ],
      child: TestMaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: BodyweightRow(profile: profile)),
      ),
    );
  }

  Widget buildToggleHost({bool initialConsent = false}) {
    return ProviderScope(
      overrides: [
        bodyweightConsentProvider.overrideWith(
          () => _StubConsent(initialConsent),
        ),
      ],
      child: TestMaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: BodyweightConsentToggle()),
      ),
    );
  }

  group('Bodyweight consent dialog (LGPD Art. 11)', () {
    testWidgets(
      'consent dialog appears on save when consent is false (default)',
      (tester) async {
        final mockRepo = _MockProfileRepository();
        const profile = Profile(id: 'user-1', weightUnit: 'kg');

        await tester.pumpWidget(
          buildEditorHost(profile: profile, repo: mockRepo),
        );
        await tester.pump();
        await tester.tap(find.text('Body weight'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '75');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        // User-visible: the consent dialog is on screen.
        expect(find.text('Body weight is sensitive data.'), findsOneWidget);
        expect(find.text('Save with consent'), findsOneWidget);
        // Repo must NOT have been called yet — consent gate held the save.
        verifyNever(
          () => mockRepo.upsertProfile(
            userId: any(named: 'userId'),
            bodyweightKg: any(named: 'bodyweightKg'),
          ),
        );
      },
    );

    testWidgets('cancelling the consent dialog dismisses it without saving', (
      tester,
    ) async {
      final mockRepo = _MockProfileRepository();
      const profile = Profile(id: 'user-1', weightUnit: 'kg');

      await tester.pumpWidget(
        buildEditorHost(profile: profile, repo: mockRepo),
      );
      await tester.pump();
      await tester.tap(find.text('Body weight'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '75');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Body weight is sensitive data.'), findsOneWidget);

      // Two Cancel buttons exist (sheet + dialog). Use the dialog's.
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();

      // User-visible: dialog gone; sheet still open (so user can retry).
      expect(find.text('Body weight is sensitive data.'), findsNothing);
      expect(find.byType(BodyweightEditorSheet), findsOneWidget);

      // No save happened.
      verifyNever(
        () => mockRepo.upsertProfile(
          userId: any(named: 'userId'),
          bodyweightKg: any(named: 'bodyweightKg'),
        ),
      );

      // PR #309 review N2 — pin that cancel truly leaves consent
      // unchanged. Tapping Save AGAIN must re-surface the consent
      // dialog. If cancel silently flipped consent we'd never see
      // the dialog a second time, and the user would have lost the
      // opportunity to make the affirmative-consent choice.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Body weight is sensitive data.'), findsOneWidget);
      expect(find.text('Save with consent'), findsOneWidget);
    });

    testWidgets(
      'tapping "Save with consent" flips the in-memory consent AND saves',
      (tester) async {
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
        final providerScopeContainer = ProviderContainer(
          overrides: [
            bodyweightConsentProvider.overrideWith(() => _StubConsent(false)),
          ],
        );
        addTearDown(providerScopeContainer.dispose);

        await tester.pumpWidget(
          buildEditorHost(profile: profile, repo: mockRepo),
        );
        await tester.pump();
        await tester.tap(find.text('Body weight'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '75');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save with consent'));
        await tester.pumpAndSettle();

        // Save happened with the entered kg.
        verify(
          () => mockRepo.upsertProfile(userId: 'user-1', bodyweightKg: 75),
        ).called(1);

        // Sheet dismissed (save completed).
        expect(find.byType(BodyweightEditorSheet), findsNothing);
      },
    );

    testWidgets(
      'when consent is already true, save proceeds without showing the dialog',
      (tester) async {
        final mockRepo = _MockProfileRepository();
        when(
          () => mockRepo.upsertProfile(
            userId: any(named: 'userId'),
            bodyweightKg: any(named: 'bodyweightKg'),
          ),
        ).thenAnswer(
          (_) async =>
              const Profile(id: 'user-1', weightUnit: 'kg', bodyweightKg: 80),
        );

        const profile = Profile(id: 'user-1', weightUnit: 'kg');

        await tester.pumpWidget(
          buildEditorHost(
            profile: profile,
            repo: mockRepo,
            initialConsent: true,
          ),
        );
        await tester.pump();
        await tester.tap(find.text('Body weight'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '80');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        // No consent dialog — already opted in.
        expect(find.text('Body weight is sensitive data.'), findsNothing);
        // Save went through.
        verify(
          () => mockRepo.upsertProfile(userId: 'user-1', bodyweightKg: 80),
        ).called(1);
        expect(find.byType(BodyweightEditorSheet), findsNothing);
      },
    );
  });

  group('BodyweightConsentToggle (withdrawal mechanism)', () {
    testWidgets('renders OFF when no consent has been given', (tester) async {
      await tester.pumpWidget(buildToggleHost(initialConsent: false));
      await tester.pump();

      expect(find.text('Body weight tracking'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, false);
    });

    testWidgets('tapping the switch flips it on (consent granted)', (
      tester,
    ) async {
      await tester.pumpWidget(buildToggleHost(initialConsent: false));
      await tester.pump();

      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      expect(tester.widget<Switch>(find.byType(Switch)).value, true);
    });

    testWidgets(
      'tapping the switch flips it off when consent was previously granted (withdrawal)',
      (tester) async {
        await tester.pumpWidget(buildToggleHost(initialConsent: true));
        await tester.pump();

        expect(tester.widget<Switch>(find.byType(Switch)).value, true);

        await tester.tap(find.byType(SwitchListTile));
        await tester.pump();

        expect(tester.widget<Switch>(find.byType(Switch)).value, false);
      },
    );

    testWidgets('subtitle pins that disabling does not delete past entries', (
      tester,
    ) async {
      await tester.pumpWidget(buildToggleHost());
      await tester.pump();

      // Pin the withdrawal-semantics copy so a future copy change can't
      // silently drop the "does not delete past entries" disclosure.
      expect(
        find.text(
          'Required to log body weight. Disabling does not delete past entries.',
        ),
        findsOneWidget,
      );
    });
  });
}
