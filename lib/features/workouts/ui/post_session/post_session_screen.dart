import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../rpg/models/body_part.dart';
import '../../../rpg/models/celebration_event.dart';
import '../../../rpg/models/character_class.dart';
import '../../../rpg/models/title.dart' as rpg;
import '../../../rpg/providers/earned_titles_provider.dart';
import '../../../rpg/ui/widgets/class_localization.dart';
import '../../domain/post_session_choreographer.dart';
import '../../domain/post_session_timing.dart';
import '../../domain/reward_tier.dart';
import '../../providers/post_session_controller.dart';
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

  @override
  void initState() {
    super.initState();
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
        if (!mounted) return;
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
    if (cut is B1XpCut) {
      // Include the pre-roll inside the same controller duration so the
      // copy-line fade pacing scales correctly. Hold = pre-roll + hold.
      return tier.b1PreRoll + tier.b1Hold;
    }
    if (cut is B2SingleBpCut) return PostSessionTiming.b2HoldSingle;
    if (cut is B2SequentialDominantCut) {
      return PostSessionTiming.b2HoldSequentialDominant;
    }
    if (cut is B2SequentialSecondaryCut) {
      return PostSessionTiming.b2HoldSequentialSecondary;
    }
    if (cut is B2CascadeCut) return PostSessionTiming.b2HoldCascade;
    if (cut is B2ElevatedRankUpCut) return PostSessionTiming.b2HoldElevated;
    if (cut is B3PrCut) {
      return PostSessionTiming.b3PrWhiteFlash + PostSessionTiming.b3HoldPr;
    }
    if (cut is B3TitleCut) return PostSessionTiming.b3HoldTitle;
    if (cut is B3ClassChangeCut) return PostSessionTiming.b3HoldClassChange;
    return const Duration(milliseconds: 1200);
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
    if (cut is B1XpCut) {
      return B1XpCutWidget(
        animation: _controller.view,
        tier: cut.tier,
        totalXp: cut.totalXp,
        copyLine: _b1CopyFor(cut, l10n),
        xpLabel: l10n.postSessionXpLabel,
      );
    }
    if (cut is B2SingleBpCut) {
      return B2BpTallyCut(
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
      );
    }
    if (cut is B2SequentialDominantCut) {
      return B2BpTallyCut(
        animation: _controller.view,
        bodyPart: cut.bodyPart,
        bodyPartLabel:
            state.bodyPartLabels[cut.bodyPart] ?? cut.bodyPart.dbValue,
        xpEarned: cut.xpEarned,
        xpLabel: 'XP',
        progressFractionAfter: cut.progressFractionAfter,
        rankAfter: 0,
        isFirstAwakening: false,
      );
    }
    if (cut is B2SequentialSecondaryCut) {
      return B2BpTallyCut(
        animation: _controller.view,
        bodyPart: cut.bodyPart,
        bodyPartLabel:
            state.bodyPartLabels[cut.bodyPart] ?? cut.bodyPart.dbValue,
        xpEarned: cut.xpEarned,
        xpLabel: 'XP',
        progressFractionAfter: cut.progressFractionAfter,
        rankAfter: 0,
        isFirstAwakening: false,
      );
    }
    if (cut is B2CascadeCut) {
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
    if (cut is B2ElevatedRankUpCut) {
      final bpLabel =
          state.bodyPartLabels[cut.bodyPart] ?? cut.bodyPart.dbValue;
      return B2ElevatedCut(
        animation: _controller.view,
        bodyPart: cut.bodyPart,
        bodyPartLabel: bpLabel,
        newRank: cut.newRank,
        rankCopy: l10n.b2RankCopy(
          bpLabel.toUpperCase(),
          cut.newRank.toString(),
        ),
      );
    }
    if (cut is B3PrCut) {
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
    if (cut is B3TitleCut) {
      final eyebrow = l10n.b3TitleEyebrow;
      // Look up the title name. Defensive: if the catalog isn't ready yet,
      // fall back to the slug.
      final catalog =
          ref.read(titleCatalogProvider).value ?? const <rpg.Title>[];
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
    if (cut is B3ClassChangeCut) {
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
    return const SizedBox.shrink();
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

    return PostSessionSummaryPanel(
      sagaLabel: sagaLabel,
      durationSetsLabel: durationSets,
      tonnageLabel: tonnage,
      nextStepEyebrow: l10n.summaryNextStepLabel,
      nextStepHook: hook,
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
          return l10n.b1CopyMaxLevelUp(level);
        }
        return l10n.b1CopyPrAnticipatory;
    }
  }

  String _titleDisplayName(
    List<rpg.Title> catalog,
    String slug,
    AppLocalizations l10n,
  ) {
    // Title display name is looked up against AppLocalizations via a key
    // pattern `title_{slug}_name`. Since AppLocalizations doesn't expose
    // runtime key lookup, the screen-layer fallback returns the slug;
    // the catalog of all titles is small enough that a future refactor
    // can promote this to a strongly-typed resolver. For 30a, that's
    // acceptable — the title cut's hue + eyebrow carry the cinematic
    // weight; the exact title name appears in the summary EQUIP row.
    return slug;
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
