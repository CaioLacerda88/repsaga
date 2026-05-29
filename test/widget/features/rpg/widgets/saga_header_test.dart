import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
import 'package:repsaga/features/rpg/ui/widgets/saga_header.dart';
import 'package:repsaga/l10n/app_localizations.dart';

/// Stub ProfileNotifier — SagaHeader's RuneHalo embeds ProfileAvatar
/// (Phase 32 PR 32e scope add) which reads `profileProvider` +
/// `currentUserEmailProvider` to resolve identity. Without the
/// override the avatar throws (`currentUserEmailProvider` touches
/// `Supabase.instance`).
class _StubProfileNotifier extends AsyncNotifier<Profile?>
    implements ProfileNotifier {
  _StubProfileNotifier(this._profile);
  final Profile? _profile;

  @override
  Future<Profile?> build() async => _profile;

  @override
  Future<void> saveOnboardingProfile({
    required String displayName,
    required String fitnessLevel,
    int trainingFrequencyPerWeek = 3,
  }) async {}

  @override
  Future<void> updateTrainingFrequency(int frequency) async {}

  @override
  Future<void> toggleWeightUnit() async {}
}

Widget _wrap(Widget child, {double width = 360}) {
  return ProviderScope(
    overrides: [
      profileProvider.overrideWith(
        () =>
            _StubProfileNotifier(const Profile(id: 'u', displayName: 'Alice')),
      ),
      currentUserEmailProvider.overrideWithValue('alice@example.test'),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('pt'),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

/// Router-backed harness for the Phase 32 PR 32e tap-to-settings test —
/// the regular [_wrap] uses a plain MaterialApp, which can't service
/// `context.push('/profile/settings')`. Mirrors the GoRouter setup in
/// `character_card_test.dart` (NoTransitionPage so we don't need
/// pumpAndSettle, which would hang on RuneHalo's infinite tickers).
Widget _wrapRouter(Widget child, {double width = 360}) {
  final router = GoRouter(
    initialLocation: '/saga',
    routes: [
      GoRoute(
        path: '/saga',
        builder: (context, state) => Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
      GoRoute(
        path: '/profile/settings',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: Scaffold(body: Text('profile-settings-placeholder')),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      profileProvider.overrideWith(
        () =>
            _StubProfileNotifier(const Profile(id: 'u', displayName: 'Alice')),
      ),
      currentUserEmailProvider.overrideWithValue('alice@example.test'),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('pt'),
      routerConfig: router,
    ),
  );
}

void main() {
  group('SagaHeader — three-column layout', () {
    testWidgets('renders rune + level numeral + class + title at 360dp', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SagaHeader(
            haloState: VitalityState.active,
            characterLevel: 14,
            characterClass: CharacterClass.bulwark,
            // Pass a real title slug from `earned_titles.title_id` — the
            // header MUST resolve it through `localizedTitleCopy(slug, l10n)`.
            // See `cluster_slug_rendered_as_display_name`.
            activeTitle: 'chest_r5_initiate_of_the_forge',
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Level numeral
      expect(find.text('14'), findsOneWidget);
      // LVL tag below the numeral
      expect(find.text('LVL'), findsOneWidget);
      // Class label resolves via localizedClassName; pt locale → "Baluarte",
      // and Phase 26b mockup spec UPPERCASE-tracks earned class names so the
      // class label sits subordinate to the 56sp LVL numeral.
      expect(find.text('BALUARTE'), findsOneWidget);
      // Active title resolves to the pt-locale display name; the raw slug
      // must NOT appear on screen.
      expect(find.text('Iniciado da Forja'), findsOneWidget);
      expect(find.text('chest_r5_initiate_of_the_forge'), findsNothing);
    });

    testWidgets('right-meta column ellipsizes long titles at 360dp', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SagaHeader(
            haloState: VitalityState.active,
            characterLevel: 14,
            characterClass: null,
            activeTitle:
                'Extraordinarily Verbose Compound Title Of The First Sun',
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The title widget renders within the meta column's 120dp clamp; the
      // ellipsis behavior is implicit if the rendered size doesn't blow up.
      final titleSize = tester.getSize(
        find.byKey(const ValueKey('saga-header-title')),
      );
      expect(
        titleSize.width,
        lessThanOrEqualTo(120),
        reason:
            'Meta column max is 120dp; the title row must clip via ellipsis.',
      );
    });

    testWidgets('omits the title row when activeTitle is null', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SagaHeader(
            haloState: VitalityState.active,
            characterLevel: 14,
            characterClass: null,
            activeTitle: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('saga-header-title')), findsNothing);
    });

    testWidgets('renders the day-1 placeholder when characterClass is null', (
      tester,
    ) async {
      // pt: "O ferro lhe dará um nome." (classSlotPlaceholder)
      await tester.pumpWidget(
        _wrap(
          const SagaHeader(
            haloState: VitalityState.active,
            characterLevel: 1,
            characterClass: null,
            activeTitle: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('ferro'), findsOneWidget);
    });

    testWidgets(
      'tapping the rune halo navigates to /profile/settings (PR 32e UX)',
      (tester) async {
        // Phase 32 PR 32e scope add: per UX-critic memo the Saga halo is a
        // tappable target that pushes `/profile/settings`. Pin the user-
        // visible behavior — after tap, the Settings placeholder content
        // renders. The `rune-halo` Semantics identifier stays (existing E2E
        // selectors anchor on it); button:true + explicitChildNodes:true
        // are added per cluster_semantics_identifier_pair_rule.
        await tester.pumpWidget(
          _wrapRouter(
            const SagaHeader(
              haloState: VitalityState.active,
              characterLevel: 14,
              characterClass: CharacterClass.bulwark,
              activeTitle: 'chest_r5_initiate_of_the_forge',
            ),
          ),
        );
        await tester.pump();

        final haloFinder = find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.identifier == 'rune-halo',
        );
        expect(
          haloFinder,
          findsOneWidget,
          reason:
              'Rune halo must carry the rune-halo Semantics identifier '
              '(existing E2E selectors depend on it).',
        );

        await tester.tap(haloFinder);
        // Single frame + small pump for the GoRouter transition; can't use
        // pumpAndSettle because the source route's RuneHalo carries an
        // infinite-loop active-state controller via _DormantHalo's parent
        // (well, active is static — but the harness still benefits from the
        // standardized single-frame swap).
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.text('profile-settings-placeholder'),
          findsOneWidget,
          reason:
              'Tapping the Saga halo must push /profile/settings (per UX-'
              'critic memo: discoverability of upload flow).',
        );
      },
    );

    testWidgets(
      'saga halo Semantics carries button:true for AOM tappable role',
      (tester) async {
        // cluster_semantics_button_missing: without button:true the AOM
        // node is passive and screen-reader / Playwright clicks don't
        // forward to the GestureDetector. Pin button:true so a refactor
        // can't silently regress.
        await tester.pumpWidget(
          _wrap(
            const SagaHeader(
              haloState: VitalityState.active,
              characterLevel: 14,
              characterClass: CharacterClass.bulwark,
              activeTitle: null,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final halo = tester.widget<Semantics>(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.identifier == 'rune-halo',
          ),
        );
        expect(halo.properties.button, isTrue);
      },
    );

    testWidgets('renders without overflow at 320dp viewport', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        _wrap(
          const SagaHeader(
            haloState: VitalityState.active,
            characterLevel: 14,
            characterClass: CharacterClass.bulwark,
            activeTitle: 'Plate-Bearer',
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final headerSize = tester.getSize(find.byType(SagaHeader));
      expect(
        headerSize.width,
        lessThanOrEqualTo(320),
        reason: 'Header must fit within a 320dp viewport without overflow.',
      );
    });
  });
}
