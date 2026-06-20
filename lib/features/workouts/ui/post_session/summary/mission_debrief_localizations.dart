import '../../../../../l10n/app_localizations.dart';

/// Pre-localized string bundle for the S2 Mission Debrief section (Phase
/// 31 Pass 3).
///
/// **Decoupling Rule 2 — widget l10n parameterization.** The debrief
/// widgets (`MissionDebriefSection`, `LiftRow`, `XpSegmentedBar`) never
/// call `AppLocalizations.of(context)` directly. The screen layer
/// resolves every needed key once via [MissionDebriefLocalizations.from]
/// and passes the bundle as a constructor param. Same pattern as
/// `ShareLocalizations` for the share flow.
///
/// **Why a flat value object instead of nesting an [AppLocalizations]?**
/// The set of keys the debrief section needs is small + well-defined; a
/// typed bundle catches a missing key at the screen-layer boundary
/// (compile-time, single touchpoint) instead of at the widget-tree-render
/// boundary (runtime, scattered across files).
class MissionDebriefLocalizations {
  const MissionDebriefLocalizations({
    required this.debriefEyebrow,
    required this.moreLifts,
    required this.nextTargetBody,
    required this.nextTargetEyebrow,
    required this.prFlag,
    required this.rankLabel,
    required this.rankUpArrow,
    required this.weightUnit,
    required this.xpEarnedLabel,
    required this.conditioningChargedEyebrow,
    required this.conditioningChargedDelta,
    required this.conditioningChargedCaption,
  });

  /// Bridge from the generated [AppLocalizations] to the typed bundle.
  /// Single touchpoint between the debrief section and the ARB layer.
  factory MissionDebriefLocalizations.from(AppLocalizations l10n) {
    return MissionDebriefLocalizations(
      debriefEyebrow: l10n.postSessionDebriefEyebrow,
      moreLifts: l10n.postSessionMoreLifts,
      nextTargetEyebrow: l10n.summaryNextStepLabel,
      nextTargetBody: l10n.summaryNextRank,
      prFlag: l10n.postSessionPrFlag,
      rankLabel: l10n.postSessionRankLabel,
      rankUpArrow: l10n.postSessionRankUpArrow,
      weightUnit: l10n.postSessionWeightUnit,
      xpEarnedLabel: l10n.postSessionXpEarnedLabel,
      conditioningChargedEyebrow: l10n.postSessionConditioningChargedEyebrow,
      conditioningChargedDelta: l10n.postSessionConditioningChargedDelta,
      conditioningChargedCaption: l10n.postSessionConditioningChargedCaption,
    );
  }

  /// "SESSION REPORT" / "RELATÓRIO DA SESSÃO" — section eyebrow.
  /// Already-localized; the widget uppercases via `toUpperCase()` at the
  /// call site so the ARB key can stay in title case.
  final String debriefEyebrow;

  /// Plural-aware "+N more exercises" footer for sessions with > 4
  /// trained exercises. Pass the COUNT of additional lifts beyond the
  /// top-4 already rendered.
  final String Function(int count) moreLifts;

  /// "Próximo passo" / "Next" — next-target callout eyebrow (reused from
  /// the legacy `summaryNextStepLabel` key).
  final String nextTargetEyebrow;

  /// Two-line body for the next-target callout: `(xp, bodyPart, rank) →
  /// "{xp} XP left\nfor {bodyPart} rank {n}."` Reused from the legacy
  /// `summaryNextRank` key (mockup §5 States 1/2/5/8).
  final String Function(int xp, String bodyPart, int n) nextTargetBody;

  /// "PR" — pre-localized PR flag rendered on the LiftRow + the alt-text
  /// for screen readers.
  final String prFlag;

  /// "Rank {n}" — used when a body part did NOT cross a rank boundary
  /// this session.
  final String Function(int rank) rankLabel;

  /// "Rank {from} → {to}" — used when a body part crossed a rank
  /// threshold this session (RankUpEvent fired).
  final String Function(int fromRank, int toRank) rankUpArrow;

  /// Weight unit suffix, e.g. "kg" / "lb". Passed into each LiftRow.
  final String weightUnit;

  /// "XP EARNED" / "XP GANHO" — right-of-numeral label rendered on the
  /// Mission Debrief XP hero block ("+340 XP EARNED"). Phase 31 round-2
  /// Bug F — was missing from the implementation; mockup Direction 2
  /// spec'd it as the FIRST child of the Mission Debrief section.
  /// Pre-uppercased to match the tracked-label register.
  final String xpEarnedLabel;

  /// "Conditioning charged" — eyebrow above the aggregate teal charge bar
  /// (Phase Vitality PR 2). Title-cased; the widget uppercases for the
  /// tracked-label register.
  final String conditioningChargedEyebrow;

  /// "+N%" delta label on the charge bar. Pass the integer percentage-point
  /// increase (afterPct − beforePct).
  final String Function(int pct) conditioningChargedDelta;

  /// "The rune recharges over ~7 days." caption locking the rebuild-not-
  /// deplete metaphor in copy.
  final String conditioningChargedCaption;
}
