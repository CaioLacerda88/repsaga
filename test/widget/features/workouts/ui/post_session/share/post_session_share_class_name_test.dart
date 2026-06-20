/// Widget tests pinning that the post-session share card surfaces the
/// LOCALIZED character-class name, never the raw class *slug*
/// ([[cluster_slug_rendered_as_display_name]]).
///
/// The regression: `_buildShareCardStrings` (private to [PostSessionScreen])
/// used to compose the achievement-frame class label as
/// `payload.characterClassSlug.toUpperCase()`, which leaked the stable
/// share/persistence token (`bulwark`, `ascendant`, …) onto the share card
/// as user-visible text instead of the translated display name
/// (`Bulwark` / `Baluarte`, `Ascendant` / `Ascendente`, …).
///
/// **Why assert on the [ShareCtaButton]'s `strings` and not a rendered
/// `Text`:** the actual class label is painted into the share card behind a
/// `RepaintBoundary` only after the user pushes the share-preview route
/// (image-picker + renderer plumbing). The `ShareCardStrings` bundle carried
/// into [ShareCtaButton] IS the composition output `_buildShareCardStrings`
/// produces — the same bundle the achievement-frame variant renders verbatim
/// (`Text(strings.achievementFrameClassName)`). Pinning the bundle pins the
/// user-perceptible card copy at the screen boundary without driving the whole
/// share-preview navigation. This is the behavior contract, not a wiring trace:
/// the only way to satisfy it is to localize the slug before it reaches the
/// card.
///
/// The regression is locale-specific (the slug `bulwark` happens to read like
/// an English word uppercased), so both `en` and `pt` are pinned — the pt
/// fixture is what actually catches the leak.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/rpg/providers/class_provider.dart';
import 'package:repsaga/features/rpg/providers/earned_titles_provider.dart';
import 'package:repsaga/features/rpg/providers/rpg_progress_provider.dart';
import 'package:repsaga/features/rpg/providers/vitality_fresh_pulse_provider.dart';
import 'package:repsaga/features/workouts/ui/post_session/post_session_controller.dart';
import 'package:repsaga/features/workouts/ui/post_session/post_session_screen.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/share_cta_button.dart';
import 'package:repsaga/l10n/app_localizations.dart';

import '../../../../../../fixtures/fake_fresh_pulse_storage.dart';

/// Builds [PostSessionParams] for a session that earns XP (so `hasShareCta`
/// is true and the share bundle gets composed). Pass [events] to drive a
/// class-change session (a [ClassChangeEvent] flips `payload.isClassChange`,
/// which switches the discreet variant to the "awakened" eyebrow copy).
PostSessionParams _params(
  AppLocalizations l10n, {
  List<CelebrationEvent> events = const [],
}) {
  return PostSessionParams(
    queueResult: CelebrationQueue.build(events: events),
    prResult: null,
    exerciseNames: const {},
    totalXpEarned: 640,
    bpXpDeltas: const {BodyPart.chest: 640},
    bpProgressFractionPre: const {},
    bpRankBefore: const {},
    bpVitalityBefore: const {},
    bpFirstAwakening: const {},
    priorFinishedWorkoutCount: 46,
    durationMinutes: 48,
    setsCount: 20,
    tonnageTons: 7.8,
    l10n: l10n,
  );
}

Widget _harness({
  required CharacterClass characterClass,
  Locale locale = const Locale('en'),
  List<CelebrationEvent> events = const [],
}) {
  return ProviderScope(
    overrides: [
      titleCatalogProvider.overrideWith((_) async => const []),
      rpgProgressProvider.overrideWith(
        () => _FakeRpgProgress(RpgProgressSnapshot.empty),
      ),
      // The share-bundle composer reads the derived class directly; override
      // the resolved value so the test pins a known class without standing up
      // a rank distribution that the resolver maps to it.
      characterClassProvider.overrideWithValue(characterClass),
      currentUserIdProvider.overrideWithValue('user-share-class-test'),
      // PostSessionScreen records the fresh-today pulse on mount; the default
      // provider opens a Hive box unavailable in this harness.
      vitalityFreshPulseLocalStorageProvider.overrideWithValue(
        FakeFreshPulseStorage(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return PostSessionScreen(
            params: _params(l10n, events: events),
            onContinue: () {},
          );
        },
      ),
    ),
  );
}

/// Drives the screen to the summary panel and returns the share bundle the
/// [ShareCtaButton] carries (the composition output of `_buildShareCardStrings`).
Future<ShareCtaButton> _shareCtaAfterSummary(WidgetTester tester) async {
  // The summary panel composes for ~760dp-tall production screens; give it
  // vertical room so the share CTA actually mounts (a too-short viewport can
  // overflow it off-screen).
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(360, 900);
  addTearDown(tester.view.reset);

  await tester.pump();
  // Long-press fast-forwards every cinematic cut and lands on the summary
  // panel, where the share CTA renders.
  await tester.longPress(find.byType(PostSessionScreen));
  await tester.pump(const Duration(milliseconds: 50));

  // Fail readably if the share CTA didn't mount (e.g. a future params change
  // flips `hasShareCta` false) instead of an opaque `tester.widget<>` throw.
  expect(find.byType(ShareCtaButton), findsOneWidget);
  final cta = tester.widget<ShareCtaButton>(find.byType(ShareCtaButton));
  addTearDown(() async {
    // Tear down without leaving the controller's pending timers behind.
    await tester.pumpWidget(const SizedBox.shrink());
  });
  return cta;
}

void main() {
  group(
    'PostSessionScreen share card — localized class name (never the slug)',
    () {
      testWidgets('achievement-frame class name is the localized en name, '
          'not the raw slug', (tester) async {
        await tester.pumpWidget(
          _harness(characterClass: CharacterClass.bulwark),
        );
        final cta = await _shareCtaAfterSummary(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        // Positive pin: en display name uppercased (resolved through l10n, not a
        // string literal — survives an editorial copy edit to the ARB).
        expect(
          cta.strings.achievementFrameClassName,
          l10n.classBulwark.toUpperCase(),
        );
        // For `bulwark` the slug+localized coincide in en, so this test alone is
        // not the regression catcher — the pt test below is. It still guards the
        // happy path doesn't regress to something else entirely.
      });

      testWidgets('achievement-frame class name is the localized pt name, '
          'not the raw slug (the locale-specific regression)', (tester) async {
        await tester.pumpWidget(
          _harness(
            characterClass: CharacterClass.bulwark,
            locale: const Locale('pt'),
          ),
        );
        final cta = await _shareCtaAfterSummary(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('pt'));
        final expected = l10n.classBulwark.toUpperCase();

        // The slug is `bulwark`; the pt display name is `Baluarte`. Before the
        // fix the card showed `BULWARK` (slug). Now it must show the localized
        // string.
        expect(cta.strings.achievementFrameClassName, expected);
        expect(cta.strings.achievementFrameClassName, isNot('BULWARK'));
      });

      testWidgets('ascendant slug resolves to its localized en display name', (
        tester,
      ) async {
        await tester.pumpWidget(
          _harness(characterClass: CharacterClass.ascendant),
        );
        final cta = await _shareCtaAfterSummary(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        expect(
          cta.strings.achievementFrameClassName,
          l10n.classAscendant.toUpperCase(),
        );
      });

      testWidgets(
        'ascendant slug resolves to its localized pt name, not the slug',
        (tester) async {
          // Parallel to the bulwark pt case: pt `Ascendente` vs slug
          // `ascendant` — a real locale-specific regression catcher.
          await tester.pumpWidget(
            _harness(
              characterClass: CharacterClass.ascendant,
              locale: const Locale('pt'),
            ),
          );
          final cta = await _shareCtaAfterSummary(tester);

          final l10n = await AppLocalizations.delegate.load(const Locale('pt'));
          expect(
            cta.strings.achievementFrameClassName,
            l10n.classAscendant.toUpperCase(),
          );
          expect(cta.strings.achievementFrameClassName, isNot('ASCENDANT'));
        },
      );

      testWidgets(
        'class-change discreet eyebrow is fully localized in pt — both the '
        'class name AND the "awakened" subline follow app locale (no mixed-'
        'locale "Baluarte DESPERTOU." regression where only the word is pt)',
        (tester) async {
          await tester.pumpWidget(
            _harness(
              characterClass: CharacterClass.bulwark,
              locale: const Locale('pt'),
              events: const [
                ClassChangeEvent(
                  fromClass: CharacterClass.initiate,
                  toClass: CharacterClass.bulwark,
                ),
              ],
            ),
          );
          final cta = await _shareCtaAfterSummary(tester);

          final l10n = await AppLocalizations.delegate.load(const Locale('pt'));
          // The eyebrow composes "{localized class} {localized subline}".
          // pt: "BALUARTE DESPERTOU." — both pieces locale-aware.
          expect(
            cta.strings.discreetEyebrow,
            '${l10n.classBulwark.toUpperCase()} ${l10n.b3ClassSubline}',
          );
          // Regression guard: must NOT be the old mix of localized class +
          // hardcoded English/other-locale framing, and must NOT leak the slug.
          expect(cta.strings.discreetEyebrow, isNot(contains('BULWARK')));
          expect(cta.strings.discreetEyebrow, contains('BALUARTE'));
          // The Discreet variant also renders the class name in the hero slot
          // (separate render path) — pin it localized too, not the slug.
          expect(cta.strings.discreetHero, l10n.classBulwark.toUpperCase());
        },
      );

      testWidgets(
        'class-change discreet eyebrow uses the en "awakened" subline in en',
        (tester) async {
          await tester.pumpWidget(
            _harness(
              characterClass: CharacterClass.bulwark,
              events: const [
                ClassChangeEvent(
                  fromClass: CharacterClass.initiate,
                  toClass: CharacterClass.bulwark,
                ),
              ],
            ),
          );
          final cta = await _shareCtaAfterSummary(tester);

          final l10n = await AppLocalizations.delegate.load(const Locale('en'));
          expect(
            cta.strings.discreetEyebrow,
            '${l10n.classBulwark.toUpperCase()} ${l10n.b3ClassSubline}',
          );
          // en subline is "AWAKENED." — the pt literal must never appear.
          expect(cta.strings.discreetEyebrow, isNot(contains('DESPERTOU')));
          // Hero slot localized too (en here, parity with the pt case above).
          expect(cta.strings.discreetHero, l10n.classBulwark.toUpperCase());
        },
      );
    },
  );
}

/// Fake [RpgProgressNotifier] resolving a pre-canned snapshot immediately.
/// The controller reads this once during init; the class itself is supplied
/// via the [characterClassProvider] override in [_harness].
class _FakeRpgProgress extends RpgProgressNotifier {
  _FakeRpgProgress(this._snapshot);
  final RpgProgressSnapshot _snapshot;
  @override
  Future<RpgProgressSnapshot> build() async => _snapshot;
}
