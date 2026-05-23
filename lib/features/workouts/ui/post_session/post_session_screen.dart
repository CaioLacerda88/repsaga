import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../rpg/models/body_part.dart';
import '../../../rpg/models/celebration_event.dart';
import '../../../rpg/models/character_class.dart';
import '../../../rpg/models/title.dart' as rpg;
import '../../../rpg/providers/earned_titles_provider.dart';
import '../../../rpg/ui/utils/vitality_state_styles.dart';
import '../../../rpg/ui/widgets/class_localization.dart';
import '../../../rpg/ui/widgets/title_localization.dart';
import '../../domain/post_session_choreographer.dart';
import '../../domain/post_session_timing.dart';
import '../../domain/reward_tier.dart';
import 'post_session_controller.dart';
import 'cuts/b1_xp_cut.dart';
import 'cuts/b2_bp_tally_cut.dart';
import 'cuts/b2_cascade_cut.dart';
import 'cuts/b2_elevated_cut.dart';
import 'cuts/b3_class_change_cut.dart';
import 'cuts/b3_pr_cut.dart';
import 'cuts/b3_title_cut.dart';
import 'post_session_state.dart';
import 'summary/next_step_hook.dart';
import 'summary/post_session_summary_panel.dart';
import 'summary/title_equip_row.dart';

/// Full-screen post-session cinematic + summary panel (Phase 30 PR 30a).
///
/// **Decoupling Rule 3 — single AnimationController.** The screen owns ONE
/// AnimationController; cut widgets receive `animation` views and render
/// against the shared timeline.
///
/// **Decoupling Rule 4 — state machine separated from rendering.** The
/// `PostSessionController` owns the cut list + index + summary flag; this
/// screen just reads the state and renders.
///
/// **Decoupling Rule 8 — route-agnostic.** Receives [onContinue] as a
/// `VoidCallback`; the route container wires GoRouter behind it.
///
/// **Decoupling Rule 9 — skip gestures via separate handler.**
/// `_handleTap` / `_handleLongPress` drive the state machine via method
/// calls on the controller; no business logic lives in the gesture
/// detector callback.
class PostSessionScreen extends ConsumerStatefulWidget {
  const PostSessionScreen({
    super.key,
    required this.params,
    required this.onContinue,
  });

  final PostSessionParams params;
  final VoidCallback onContinue;

  @override
  ConsumerState<PostSessionScreen> createState() => _PostSessionScreenState();
}

class _PostSessionScreenState extends ConsumerState<PostSessionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final PostSessionController _stateController;

  /// Duration for the current cut. Updated whenever the cut index changes.
  Duration _currentCutDuration = const Duration(milliseconds: 1200);

  /// True after [dispose] runs. Guards the abyss-gap [Future.delayed]
  /// callback against firing after teardown — `mounted` alone is
  /// insufficient when synthetic test clocks resolve the timer before the
  /// State's `BuildContext` notices unmounting.
  bool _disposed = false;

  /// TEMP-INSTRUMENTATION (cinematic-not-playing diagnosis) — REVERT.
  /// Guards the one-shot "first build" log so we don't spam every rebuild.
  bool _loggedFirstBuild = false;

  @override
  void initState() {
    super.initState();
    // TEMP-INSTRUMENTATION (cinematic-not-playing diagnosis) — REVERT
    developer.log(
      'POST-SESSION-SCREEN: initState fired, '
      'priorFinishedWorkoutCount=${widget.params.priorFinishedWorkoutCount}, '
      'totalXpEarned=${widget.params.totalXpEarned}, '
      'queueLen=${widget.params.queueResult.queue.length}',
      name: 'repsaga',
    );
    _stateController = PostSessionController(ref: ref, params: widget.params);
    _controller = AnimationController(
      vsync: this,
      duration: _currentCutDuration,
    );

    // Kick off the first cut after the initial state is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _playCurrentCut();
    });

    _controller.addStatusListener(_onAnimationStatus);
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.removeStatusListener(_onAnimationStatus);
    _controller.dispose();
    _stateController.dispose();
    super.dispose();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final state = _stateController.state;
    if (state.isPlayingCinematic) {
      // Schedule advance after the abyss gap; we defer one frame so the
      // current cut's last frame paints before the swap. Future.microtask
      // would skip the abyss gap; we want a deliberate blackout.
      Future.delayed(PostSessionTiming.cutAbyssGap, () {
        // Defensive double-guard: `_disposed` catches the synthetic-clock
        // race where the timer resolves after [dispose] but before the
        // framework marks the State as unmounted; `mounted` catches the
        // common path. Either alone leaks a use-after-dispose on the
        // controller fields in tests using `tester.runAsync` + a fake
        // ticker.
        if (_disposed || !mounted) return;
        _stateController.advance();
        _playCurrentCut();
      });
    }
  }

  void _playCurrentCut() {
    if (!mounted) return;
    final state = _stateController.state;
    if (!state.isPlayingCinematic) return;
    final cut = state.cuts[state.cutIndex];
    final duration = _durationForCut(cut, state.tier);
    if (duration != _currentCutDuration) {
      _currentCutDuration = duration;
      _controller.duration = duration;
    }
    _controller.value = 0.0;
    _controller.forward();
  }

  Duration _durationForCut(PostSessionCut cut, RewardTier tier) {
    // Exhaustive switch on the sealed [PostSessionCut] union — a future
    // Beat 3 variant added to the union will produce a compile error here
    // (non_exhaustive_switch_expression), not a silent fallback duration.
    return switch (cut) {
      // Include the pre-roll inside the same controller duration so the
      // copy-line fade pacing scales correctly. Hold = pre-roll + hold.
      B1XpCut() => tier.b1PreRoll + tier.b1Hold,
      B2SingleBpCut() => PostSessionTiming.b2HoldSingle,
      B2SequentialDominantCut() => PostSessionTiming.b2HoldSequentialDominant,
      B2SequentialSecondaryCut() => PostSessionTiming.b2HoldSequentialSecondary,
      B2CascadeCut() => PostSessionTiming.b2HoldCascade,
      B2ElevatedRankUpCut() => PostSessionTiming.b2HoldElevated,
      B3PrCut() =>
        PostSessionTiming.b3PrWhiteFlash + PostSessionTiming.b3HoldPr,
      B3TitleCut() => PostSessionTiming.b3HoldTitle,
      B3ClassChangeCut() => PostSessionTiming.b3HoldClassChange,
    };
  }

  void _handleTap() {
    if (_stateController.state.showSummary) return;
    _controller.stop();
    _stateController.advance();
    _playCurrentCut();
  }

  void _handleLongPress() {
    if (_stateController.state.showSummary) return;
    _controller.stop();
    _stateController.skipToSummary();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'post-session-screen',
      child: Scaffold(
        backgroundColor: AppColors.abyss,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onLongPress: _handleLongPress,
          child: ListenableBuilder(
            listenable: _stateController,
            builder: (context, _) {
              final state = _stateController.state;
              // TEMP-INSTRUMENTATION (cinematic-not-playing diagnosis) — REVERT
              if (!_loggedFirstBuild) {
                _loggedFirstBuild = true;
                developer.log(
                  'POST-SESSION-SCREEN: building cuts, '
                  'rewardTier=${state.tier}, '
                  'cutCount=${state.cuts.length}, '
                  'showSummary=${state.showSummary}',
                  name: 'repsaga',
                );
              }
              return state.showSummary
                  ? _buildSummary(state, l10n)
                  : _buildCinematic(state, l10n);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCinematic(PostSessionState state, AppLocalizations l10n) {
    final cut = state.cuts[state.cutIndex];
    return AnimatedSwitcher(
      duration: Duration.zero,
      child: KeyedSubtree(
        key: ValueKey(state.cutIndex),
        child: _buildCut(cut, state, l10n),
      ),
    );
  }

  Widget _buildCut(
    PostSessionCut cut,
    PostSessionState state,
    AppLocalizations l10n,
  ) {
    // Exhaustive switch on the sealed [PostSessionCut] union — no default
    // arm. A future Beat variant added to the union surfaces a compile
    // error here (non_exhaustive_switch_expression) instead of silently
    // rendering an empty SizedBox.
    return switch (cut) {
      B1XpCut() => B1XpCutWidget(
        animation: _controller.view,
        tier: cut.tier,
        totalXp: cut.totalXp,
        copyLine: _b1CopyFor(cut, l10n),
        xpLabel: l10n.postSessionXpLabel,
      ),
      B2SingleBpCut() => B2BpTallyCut(
        animation: _controller.view,
        bodyPart: cut.bodyPart,
        bodyPartLabel:
            state.bodyPartLabels[cut.bodyPart] ?? cut.bodyPart.dbValue,
        xpEarned: cut.xpEarned,
        xpLabel: 'XP',
        progressFractionAfter: cut.progressFractionAfter,
        rankAfter: cut.rankAfter,
        isFirstAwakening: cut.isFirstAwakening,
        firstAwakeningSuffix: cut.isFirstAwakening
            ? ' · ${l10n.postSessionFirstAwakeningSuffix}'
            : null,
      ),
      B2SequentialDominantCut() => B2BpTallyCut(
        animation: _controller.view,
        bodyPart: cut.bodyPart,
        bodyPartLabel:
            state.bodyPartLabels[cut.bodyPart] ?? cut.bodyPart.dbValue,
        xpEarned: cut.xpEarned,
        xpLabel: 'XP',
        progressFractionAfter: cut.progressFractionAfter,
        rankAfter: 0,
        isFirstAwakening: false,
      ),
      B2SequentialSecondaryCut() => B2BpTallyCut(
        animation: _controller.view,
        bodyPart: cut.bodyPart,
        bodyPartLabel:
            state.bodyPartLabels[cut.bodyPart] ?? cut.bodyPart.dbValue,
        xpEarned: cut.xpEarned,
        xpLabel: 'XP',
        progressFractionAfter: cut.progressFractionAfter,
        rankAfter: 0,
        isFirstAwakening: false,
      ),
      B2CascadeCut() => _buildCascadeCut(cut, state, l10n),
      B2ElevatedRankUpCut() => _buildElevatedCut(cut, state, l10n),
      B3PrCut() => _buildPrCut(cut, l10n),
      B3TitleCut() => _buildTitleCut(cut, state, l10n),
      B3ClassChangeCut() => _buildClassChangeCut(cut, l10n),
    };
  }

  Widget _buildCascadeCut(
    B2CascadeCut cut,
    PostSessionState state,
    AppLocalizations l10n,
  ) {
    final truncated = cut.truncatedCount > 0
        ? l10n.postSessionCascadeTruncationPill(cut.truncatedCount.toString())
        : '';
    return B2CascadeCutWidget(
      animation: _controller.view,
      cut: cut,
      bodyPartLabels: state.bodyPartLabels,
      xpLabel: l10n.postSessionXpLabel,
      truncatedPillLabel: truncated,
    );
  }

  Widget _buildElevatedCut(
    B2ElevatedRankUpCut cut,
    PostSessionState state,
    AppLocalizations l10n,
  ) {
    final bpLabel = state.bodyPartLabels[cut.bodyPart] ?? cut.bodyPart.dbValue;
    return B2ElevatedCut(
      animation: _controller.view,
      bodyPart: cut.bodyPart,
      bodyPartLabel: bpLabel,
      newRank: cut.newRank,
      rankCopy: l10n.b2RankCopy(bpLabel.toUpperCase(), cut.newRank.toString()),
    );
  }

  Widget _buildPrCut(B3PrCut cut, AppLocalizations l10n) {
    final isMulti = cut.pillRows.isNotEmpty;
    final eyebrow = isMulti
        ? l10n.b3PrEyebrowMulti(cut.pillRows.length + 1)
        : l10n.b3PrEyebrowSingle;
    final copy = isMulti ? l10n.b3PrCopyMulti : l10n.b3PrCopySingle;
    final pillLabels = [
      for (final pr in cut.pillRows)
        l10n.b3PrPillTemplate(
          pr.exerciseName,
          _formatWeight(pr.weightKg),
          pr.reps,
        ),
    ];
    final truncated = cut.truncatedPillCount > 0
        ? l10n.postSessionCascadeTruncationPill(
            cut.truncatedPillCount.toString(),
          )
        : '';
    return B3PrCutWidget(
      animation: _controller.view,
      data: B3PrCutData.fromCut(cut),
      eyebrow: eyebrow,
      copyLine: copy,
      pillLabels: pillLabels,
      truncatedPillLabel: truncated,
    );
  }

  Widget _buildTitleCut(
    B3TitleCut cut,
    PostSessionState state,
    AppLocalizations l10n,
  ) {
    final eyebrow = l10n.b3TitleEyebrow;
    // Defensive catalog read: if the title catalog provider is mid-load,
    // [localizedTitleCopy] falls back to the slug — never the steady-state
    // path (cluster: slug-rendered-as-display-name).
    final catalog = ref.read(titleCatalogProvider).value ?? const <rpg.Title>[];
    final titleName = _titleDisplayName(catalog, cut.titleSlug, l10n);
    final sub = _titleSubLabel(catalog, cut.titleSlug, l10n, state);
    final bp = _titleBodyPart(catalog, cut.titleSlug);
    return B3TitleCutWidget(
      animation: _controller.view,
      variant: cut.variant,
      titleName: titleName,
      subLabel: sub,
      eyebrowLabel: eyebrow,
      bodyPart: bp,
    );
  }

  Widget _buildClassChangeCut(B3ClassChangeCut cut, AppLocalizations l10n) {
    final cls = CharacterClass.values.firstWhere(
      (c) => c.slug == cut.toClassSlug,
      orElse: () => CharacterClass.initiate,
    );
    final copy = localizedClassCopy(cls, l10n);
    return B3ClassChangeCutWidget(
      animation: _controller.view,
      className: copy.name.toUpperCase(),
      eyebrowLabel: l10n.b3ClassEyebrow,
      subLabel: l10n.b3ClassSubline,
      flavorLine: copy.tagline,
    );
  }

  Widget _buildSummary(PostSessionState state, AppLocalizations l10n) {
    final sagaLabel = state.priorFinishedWorkoutCount == 0
        ? l10n.summaryDayZero
        : l10n.summarySagaNumber(state.sagaNumber);
    final durationSets = l10n.summaryDurationSets(
      state.durationMinutes,
      state.setsCount,
    );
    final tonnage = l10n.summaryTonnage(state.tonnageTons.toStringAsFixed(1));

    // Build optional rows.
    Widget? titleRow;
    final titleEvents = state.queueResult.queue
        .whereType<TitleUnlockEvent>()
        .toList();
    if (titleEvents.isNotEmpty) {
      final catalog =
          ref.read(titleCatalogProvider).value ?? const <rpg.Title>[];
      final slug = titleEvents.first.slug;
      titleRow = TitleEquipRow(
        eyebrowLabel: l10n.summaryNewTitleLabel,
        titleName: _titleDisplayName(catalog, slug, l10n),
        equipLabel: l10n.summaryEquipCta,
        laterLabel: l10n.summaryEquipLater,
        equippedLabel: l10n.postSessionTitleEquipped,
        onEquipPressed: () async {
          final repo = ref.read(titlesRepositoryProvider);
          await repo.equipTitle(slug);
          ref.invalidate(earnedTitlesProvider);
          ref.invalidate(equippedTitleSlugProvider);
        },
      );
    }

    Widget? overflowRow;
    final rankUpEvents = state.queueResult.queue
        .whereType<RankUpEvent>()
        .toList();
    // The "elevated" cut consumes the top rank-up; remaining rank-ups
    // (if any) surface here. Mockup §5 State 6.
    final additionalRankUps = rankUpEvents.length > 1
        ? rankUpEvents.skip(1).toList()
        : <RankUpEvent>[];
    if (additionalRankUps.isNotEmpty) {
      final r = additionalRankUps.first;
      overflowRow = RankUpOverflowRow(
        bodyPart: r.bodyPart,
        bodyPartLabel: state.bodyPartLabels[r.bodyPart] ?? r.bodyPart.dbValue,
        newRank: r.newRank,
        headerLabel: l10n.summaryRankUpOverflowHeader,
      );
    }

    // Build next-step hook.
    final hook = NextStepHookResolver.resolve(
      hasLevelUp: state.nextLevel != null,
      prDetail: null, // PR detail surfaces in a dedicated row below.
      dominantBodyPart: state.dominantBodyPart,
      dominantXpToNextRank: state.dominantXpToNextRank,
      dominantNextRank: state.dominantNextRank,
      ranksToNextLevel: state.ranksToNextLevel,
      nextLevel: state.nextLevel,
    );

    // Mockup §5 per-state eyebrow color rule:
    //   * NextRankHook → dominant BP's hue (matches the §5 State 1/2/5/6/8
    //     pattern where the forward hook is anchored to the muscle the
    //     user just trained, even when the eyebrow text is generic).
    //   * NextLevelHook → hotViolet (character-level milestones live on
    //     the brand-primary axis, not a body-part identity — mockup §5
    //     State 7 + 10).
    //   * null (no hook) → defaults to hotViolet at the panel layer.
    // PR-detail eyebrow on mockup §5 State 3 uses the heroGold accent
    // ("!! Recorde" tracked caption — `color: var(--hero-gold)` on
    // `.t-label-sm`). Wrapping a single Text color in a RewardAccent
    // ancestor would require lifting the entire panel for one tracked
    // caption — the gold here is a typographic accent, not a foreground
    // reward burst. The ignore marker lives on the line itself (form a)
    // so `dart format` cannot orphan it.
    final eyebrowColor = switch (hook) {
      NextRankHook(:final bodyPart) =>
        VitalityStateStyles.bodyPartColor[bodyPart] ?? AppColors.hotViolet,
      NextLevelHook() => AppColors.hotViolet,
      PrDetailHook() =>
        AppColors
            .heroGold, // ignore: reward_accent — typographic accent, see header
      null => AppColors.hotViolet,
    };

    return PostSessionSummaryPanel(
      sagaLabel: sagaLabel,
      durationSetsLabel: durationSets,
      tonnageLabel: tonnage,
      nextStepEyebrow: l10n.summaryNextStepLabel,
      nextStepHook: hook,
      nextStepEyebrowColor: eyebrowColor,
      continueLabel: l10n.summaryContinueCta,
      shareLabel: l10n.summaryShareCta,
      shareComingSoonMessage: l10n.summaryShareComingSoon,
      hasShareCta: state.hasShareCta,
      titleEquipRow: titleRow,
      rankUpOverflow: overflowRow,
      onContinue: () {
        _stateController.onContinue();
        widget.onContinue();
      },
      nextStepHookFormatter: (h) => _formatHook(h, state, l10n),
    );
  }

  String _formatHook(
    NextStepHookKind hook,
    PostSessionState state,
    AppLocalizations l10n,
  ) {
    return switch (hook) {
      NextRankHook(:final bodyPart, :final xpToNextRank, :final nextRank) =>
        l10n.summaryNextRank(
          xpToNextRank,
          state.bodyPartLabels[bodyPart] ?? bodyPart.dbValue,
          nextRank,
        ),
      NextLevelHook(:final ranksToNextLevel, :final nextLevel) =>
        l10n.summaryNextLevel(ranksToNextLevel, nextLevel),
      PrDetailHook(
        :final exerciseName,
        :final weightKg,
        :final reps,
        :final improvementKg,
      ) =>
        // PR detail rendering — defensive fallback (PRDetailHook isn't
        // wired in 30a; PR detail surfaces via the dedicated B3 PR cut).
        '$exerciseName · ${weightKg.toStringAsFixed(0)}kg × $reps · +${improvementKg.toStringAsFixed(0)}kg',
    };
  }

  String _b1CopyFor(B1XpCut cut, AppLocalizations l10n) {
    switch (cut.tier) {
      case RewardTier.dayZero:
        return l10n.b1CopyDayZero;
      case RewardTier.baseline:
        return cut.baselineCopyVariant == BaselineCopyVariant.a
            ? l10n.b1CopyBaselineA
            : l10n.b1CopyBaselineB;
      case RewardTier.thresholdAnticipatory:
        // Title-anticipatory state (State 8) reuses this variant with
        // a distinct copy line per mockup §2 note. Pick the title copy
        // when a title-unlock event is queued.
        final hasTitleUnlock = _stateController.state.queueResult.queue.any(
          (e) => e is TitleUnlockEvent,
        );
        return hasTitleUnlock
            ? l10n.b1CopyTitleAnticipatory
            : l10n.b1CopyPrAnticipatory;
      case RewardTier.classChangeAnticipatory:
        final level = cut.newCharacterLevel;
        if (level != null) {
          // Max-combo / level-up folds the level into the B1 copy via the
          // Max variant (mockup §5 State 7/10).
          return l10n.b1CopyMaxLevelUp(level);
        }
        // State 9 (class-change-only): the bottom copy line is its OWN
        // ARB key, not a reuse of the PR-anticipatory string. The text
        // happens to be the same today ("NEW LIMIT." / "NOVO LIMITE." per
        // mockup §5 State 9), but routing through a dedicated key keeps
        // future editorial divergence cost-free and removes the semantic
        // mis-route the State 9 fallback otherwise telegraphs.
        return l10n.b1CopyClassChangeOnly;
    }
  }

  String _titleDisplayName(
    List<rpg.Title> catalog,
    String slug,
    AppLocalizations l10n,
  ) {
    // Resolve the localized display name via the project-wide title slug →
    // ARB-key resolver (mirrors how the Titles screen renders names — see
    // `lib/features/rpg/ui/widgets/title_localization.dart`). The catalog
    // parameter is preserved so the call site can stay stable if the
    // resolver future grows to take a richer key. Falls back to the slug
    // only when the catalog is mid-load AND the slug isn't yet in the
    // resolver — never the steady-state path (cluster:
    // slug-rendered-as-display-name).
    return localizedTitleCopy(slug, l10n)?.name ?? slug;
  }

  String _titleSubLabel(
    List<rpg.Title> catalog,
    String slug,
    AppLocalizations l10n,
    PostSessionState state,
  ) {
    final t = catalog.where((c) => c.slug == slug).firstOrNull;
    if (t == null) return slug;
    return switch (t) {
      rpg.BodyPartTitle(:final bodyPart, :final rankThreshold) =>
        '${state.bodyPartLabels[bodyPart] ?? bodyPart.dbValue} · rank $rankThreshold.',
      rpg.CharacterLevelTitle(:final levelThreshold) => l10n.b1CopyMaxLevelUp(
        levelThreshold,
      ),
      rpg.CrossBuildTitle() => '',
    };
  }

  BodyPart? _titleBodyPart(List<rpg.Title> catalog, String slug) {
    final t = catalog.where((c) => c.slug == slug).firstOrNull;
    return switch (t) {
      rpg.BodyPartTitle(:final bodyPart) => bodyPart,
      _ => null,
    };
  }

  /// Format a kg value — drops the decimal when whole.
  String _formatWeight(double w) {
    if (w == w.roundToDouble()) return w.toStringAsFixed(0);
    return w.toStringAsFixed(1);
  }
}
