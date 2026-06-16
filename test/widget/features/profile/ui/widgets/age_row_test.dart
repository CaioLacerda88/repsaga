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
import 'package:repsaga/features/profile/ui/widgets/age_row.dart';
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
    registerFallbackValue(DateTime(2000));
  });

  Widget buildHost({
    Profile? profile,
    _MockProfileRepository? repo,
    double textScale = 1.0,
    Locale locale = const Locale('en'),
  }) {
    final mockRepo = repo ?? _MockProfileRepository();
    final mockAuth = _MockAuthRepository();
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
        // Apply the text scaler app-wide (via builder) so it also reaches the
        // AgeEditorSheet modal route, which is pushed onto the root navigator
        // and would otherwise miss a MediaQuery wrapped only around AgeRow.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: AgeRow(profile: profile)),
      ),
    );
  }

  group('deriveAge', () {
    test('returns null when dob is null', () {
      expect(AgeRow.deriveAge(null), isNull);
    });

    test('returns whole years from a YYYY-01-01 date', () {
      final now = DateTime(2026, 6, 16);
      expect(AgeRow.deriveAge(DateTime(1987, 1, 1), now: now), 39);
    });

    test('counts a birthday that has not occurred yet as the prior age', () {
      final now = DateTime(2026, 3, 1);
      // Born June 15 — birthday hasn't happened by March 1.
      expect(AgeRow.deriveAge(DateTime(1990, 6, 15), now: now), 35);
    });
  });

  group('AgeRow', () {
    testWidgets('renders "Not set" when profile.dateOfBirth is null', (
      tester,
    ) async {
      const profile = Profile(id: 'user-1');

      await tester.pumpWidget(buildHost(profile: profile));
      await tester.pump();

      expect(find.text('Age'), findsOneWidget);
      expect(find.text('Not set'), findsOneWidget);
    });

    testWidgets('renders no warning icon in the not-set state', (tester) async {
      const profile = Profile(id: 'user-1');

      await tester.pumpWidget(buildHost(profile: profile));
      await tester.pump();

      // Calm invitation — never an error/warning affordance.
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

    testWidgets('renders the derived age, not the raw year, when set', (
      tester,
    ) async {
      final birthYear = DateTime.now().year - 30;
      final profile = Profile(
        id: 'user-1',
        dateOfBirth: DateTime(birthYear, 1),
      );

      await tester.pumpWidget(buildHost(profile: profile));
      await tester.pump();

      // Derived age "30" is shown; the raw stored year is NOT.
      expect(find.text('30'), findsOneWidget);
      expect(find.text('$birthYear'), findsNothing);
    });

    testWidgets('tapping the row opens the AgeEditorSheet', (tester) async {
      const profile = Profile(id: 'user-1');

      await tester.pumpWidget(buildHost(profile: profile));
      await tester.pump();

      await tester.tap(find.text('Age'));
      await tester.pumpAndSettle();

      expect(find.byType(AgeEditorSheet), findsOneWidget);
      // Disclosure helper present; NO consent banner/toggle (Art. 6).
      expect(
        find.textContaining('We use your age to score cardio'),
        findsOneWidget,
      );
    });

    testWidgets('row tap target is at least 48dp tall', (tester) async {
      const profile = Profile(id: 'user-1');

      await tester.pumpWidget(buildHost(profile: profile));
      await tester.pump();

      final size = tester.getSize(find.byType(InkWell).first);
      expect(size.height, greaterThanOrEqualTo(48.0));
    });
  });

  group('AgeEditorSheet', () {
    testWidgets('cannot select an under-18 year (structural ≥18 floor)', (
      tester,
    ) async {
      const profile = Profile(id: 'user-1');

      await tester.pumpWidget(buildHost(profile: profile));
      await tester.pump();
      await tester.tap(find.text('Age'));
      await tester.pumpAndSettle();

      final currentYear = DateTime.now().year;
      // The youngest selectable birth year corresponds to age 18; an
      // under-18 birth year (age 17) is structurally absent from the wheel.
      final under18Year = currentYear - 17;
      // Scroll the wheel hard toward the top (youngest years).
      await tester.drag(
        find.byType(ListWheelScrollView),
        const Offset(0, 4000),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('$under18Year'),
        findsNothing,
        reason:
            'The wheel must not represent an under-18 birth year — the ≥18 '
            'floor is structural, never re-asking the signup age gate.',
      );
    });

    testWidgets('Save writes upsertProfile with January-1 of the picked year', (
      tester,
    ) async {
      final mockRepo = _MockProfileRepository();
      when(
        () => mockRepo.upsertProfile(
          userId: any(named: 'userId'),
          dateOfBirth: any(named: 'dateOfBirth'),
        ),
      ).thenAnswer((_) async => const Profile(id: 'user-1'));

      const profile = Profile(id: 'user-1');

      await tester.pumpWidget(buildHost(profile: profile, repo: mockRepo));
      await tester.pump();
      await tester.tap(find.text('Age'));
      await tester.pumpAndSettle();

      // Default rest is currentYear − 35.
      final expectedYear = DateTime.now().year - 35;

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final captured =
          verify(
                () => mockRepo.upsertProfile(
                  userId: 'user-1',
                  dateOfBirth: captureAny(named: 'dateOfBirth'),
                ),
              ).captured.single
              as DateTime;
      expect(captured.year, expectedYear);
      expect(captured.month, 1);
      expect(captured.day, 1);

      // Sheet dismisses.
      expect(find.byType(AgeEditorSheet), findsNothing);
    });

    testWidgets(
      '"Prefer not to say" clears to NULL via clearDateOfBirth and pops',
      (tester) async {
        final mockRepo = _MockProfileRepository();
        when(() => mockRepo.clearDateOfBirth(any())).thenAnswer((_) async {});

        // A previously-set value — PNS must clear it.
        final profile = Profile(
          id: 'user-1',
          dateOfBirth: DateTime(1990, 1, 1),
        );

        await tester.pumpWidget(buildHost(profile: profile, repo: mockRepo));
        await tester.pump();
        await tester.tap(find.text('Age'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Prefer not to say'));
        await tester.pumpAndSettle();

        verify(() => mockRepo.clearDateOfBirth('user-1')).called(1);
        verifyNever(
          () => mockRepo.upsertProfile(
            userId: any(named: 'userId'),
            dateOfBirth: any(named: 'dateOfBirth'),
          ),
        );
        expect(find.byType(AgeEditorSheet), findsNothing);
      },
    );

    testWidgets('Cancel closes the sheet without writing', (tester) async {
      final mockRepo = _MockProfileRepository();
      const profile = Profile(id: 'user-1');

      await tester.pumpWidget(buildHost(profile: profile, repo: mockRepo));
      await tester.pump();
      await tester.tap(find.text('Age'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(
        () => mockRepo.upsertProfile(
          userId: any(named: 'userId'),
          dateOfBirth: any(named: 'dateOfBirth'),
        ),
      );
      verifyNever(() => mockRepo.clearDateOfBirth(any()));
      expect(find.byType(AgeEditorSheet), findsNothing);
    });

    testWidgets('Cancel / Save action buttons meet the 48dp tap floor', (
      tester,
    ) async {
      const profile = Profile(id: 'user-1');

      await tester.pumpWidget(buildHost(profile: profile));
      await tester.pump();
      await tester.tap(find.text('Age'));
      await tester.pumpAndSettle();

      final saveSize = tester.getSize(
        find.widgetWithText(FilledButton, 'Save'),
      );
      final cancelSize = tester.getSize(
        find.widgetWithText(TextButton, 'Cancel'),
      );
      expect(saveSize.height, greaterThanOrEqualTo(48.0));
      expect(cancelSize.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('center year does not clip at textScaler 1.3', (tester) async {
      const profile = Profile(id: 'user-1');

      await tester.pumpWidget(buildHost(profile: profile, textScale: 1.3));
      await tester.pump();
      await tester.tap(find.text('Age'));
      await tester.pumpAndSettle();

      // The selected (center) year is rendered. At 1.3 scale the item
      // extent grows off the scaled metric, so the Text lays out within
      // its slot without an overflow error (an overflow throws during
      // pump in test mode). Reaching this assertion means no clip/overflow.
      final selectedYear = DateTime.now().year - 35;
      expect(find.text('$selectedYear'), findsOneWidget);

      // The wheel itself fits inside the (scrollable) sheet without the
      // center numeral's painted height exceeding the per-item extent —
      // assert the rendered numeral height stays under the scaled extent.
      final yearSize = tester.getSize(find.text('$selectedYear').first);
      final scaledExtent = const TextScaler.linear(1.3).scale(52.0);
      expect(yearSize.height, lessThanOrEqualTo(scaledExtent));
    });
  });

  // Narrow-device regression guards (responsive-layout-real-devices lesson):
  // every layout must survive the smallest Android (320dp), baseline (360dp),
  // and large-phone (412dp) logical widths — in BOTH locales, since pt-BR
  // strings ("Não informado", "Prefiro não informar", the disclosure line)
  // run longer than EN. An overflow throws a FlutterError during pump in test
  // mode, surfacing via `tester.takeException()`.
  group('AgeRow narrow-width layout', () {
    void setNarrow(WidgetTester tester, double width) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    for (final locale in const [Locale('en'), Locale('pt')]) {
      for (final width in const [320.0, 360.0, 412.0]) {
        testWidgets(
          'does not overflow at ${width}dp (${locale.languageCode}), unset',
          (tester) async {
            setNarrow(tester, width);
            const profile = Profile(id: 'user-1');

            await tester.pumpWidget(
              buildHost(profile: profile, locale: locale),
            );
            await tester.pump();

            expect(tester.takeException(), isNull);
          },
        );
      }

      // Set state with the longest derived-age value ("100" / "100 anos").
      testWidgets(
        'does not overflow at 320dp (${locale.languageCode}), long age value',
        (tester) async {
          setNarrow(tester, 320.0);
          final profile = Profile(
            id: 'user-1',
            dateOfBirth: DateTime(DateTime.now().year - 100, 1),
          );

          await tester.pumpWidget(buildHost(profile: profile, locale: locale));
          await tester.pump();

          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('AgeEditorSheet narrow-width layout', () {
    void setNarrow(WidgetTester tester, double width) {
      // Tall surface so vertical Column content (helper line, wheel, PNS,
      // buttons) lays out without a vertical overflow masking the horizontal
      // checks we care about.
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    for (final locale in const [Locale('en'), Locale('pt')]) {
      for (final width in const [320.0, 360.0, 412.0]) {
        testWidgets(
          'does not overflow at ${width}dp (${locale.languageCode})',
          (tester) async {
            setNarrow(tester, width);
            const profile = Profile(id: 'user-1');

            await tester.pumpWidget(
              buildHost(profile: profile, locale: locale),
            );
            await tester.pump();
            await tester.tap(find.byType(AgeRow));
            await tester.pumpAndSettle();

            // Sheet open — disclosure line, wheel, PNS, Cancel/Save row all
            // laid out at this width without a RenderFlex overflow.
            expect(find.byType(AgeEditorSheet), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }

      // Narrow width COMBINED with the 1.3 accessibility scale — the harshest
      // realistic case for the wheel band (derived-age tag) + button row.
      testWidgets(
        'does not overflow at 320dp x1.3 scale (${locale.languageCode})',
        (tester) async {
          setNarrow(tester, 320.0);
          const profile = Profile(id: 'user-1');

          await tester.pumpWidget(
            buildHost(profile: profile, locale: locale, textScale: 1.3),
          );
          await tester.pump();
          await tester.tap(find.byType(AgeRow));
          await tester.pumpAndSettle();

          expect(find.byType(AgeEditorSheet), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
