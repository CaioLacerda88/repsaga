import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/device/platform_info.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../analytics/data/models/analytics_event.dart';
import '../../../analytics/providers/analytics_providers.dart';
import '../../../auth/providers/auth_providers.dart';
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
import '../../domain/share_payload.dart';
import '../../../rpg/providers/class_provider.dart';
import 'cuts/b3_pr_cut.dart';
import 'cuts/b3_title_cut.dart';
import 'cuts/cinematic_skip_button.dart';
import 'cuts/cinematic_tap_hint.dart';
import 'post_session_state.dart';
import 'share/share_card_renderer.dart';
import 'share/share_localizations.dart';
import 'summary/mission_debrief_localizations.dart';
import 'summary/mission_debrief_section.dart';
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

  /// PR 30a UX pass — tracks whether the user has tapped the cinematic
  /// at least once. The tap-hint affordance disappears permanently after
  /// the first tap (or after [_tapHintExpired] flips at 2s, whichever
  /// fires first). Once true, never resets — the user has confirmed they
  /// know the gesture exists.
  bool _userHasTapped = false;

  /// PR 30a UX pass — flipped true by a one-shot 2000ms `Timer` scheduled
  /// in [initState]. After 2 seconds of B1, the tap-hint affordance hides
  /// regardless of whether the user tapped (the cinematic has moved on; the
  /// affordance is no longer relevant for that surface). The check is
  /// composed in [_buildCinematic] alongside the `_userHasTapped` +
  /// `cutIndex == 0` predicates so the hint truly fires once per session.
  bool _tapHintExpired = false;

  /// PR 30a UX pass — owns the 2000ms tap-hint retirement timer so
  /// [dispose] can cancel it before teardown. `Future.delayed` is not
  /// cancellable; a pending Future trips the test framework's
  /// `timersPending` assertion when the host widget unmounts before the
  /// 2s elapses.
  Timer? _tapHintTimer;

  /// Phase 32 PR 32d — one-shot guard for the
  /// `post_session_cinematic_shown` + per-title `title_unlocked` events.
  /// `initState` schedules a single post-frame callback that emits both;
  /// this flag prevents Riverpod rebuilds (or hot-reload) from re-firing
  /// the events. Structural guarantee preferred over a flag would require
  /// pinning the screen mount to a one-shot widget, which is heavier than
  /// a single bool for an analytics emit-site.
  bool _analyticsFired = false;

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
      _fireMountAnalytics();
      _playCurrentCut();
    });

    _controller.addStatusListener(_onAnimationStatus);

    // PR 30a UX pass — schedule the tap-hint retirement at 2000ms via a
    // cancellable [Timer] so [dispose] can drop it before teardown
    // ([Future.delayed] is not cancellable and trips the test framework's
    // `timersPending` assertion when the screen unmounts before 2s
    // elapses). If the user taps before this fires, [_userHasTapped] is
    // the primary gate and this timer's flip is a no-op for hint
    // visibility (the OR-condition already retired the affordance).
    _tapHintTimer = Timer(const Duration(milliseconds: 2000), () {
      if (_disposed || !mounted) return;
      if (_tapHintExpired) return;
      setState(() => _tapHintExpired = true);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _tapHintTimer?.cancel();
    _controller.removeStatusListener(_onAnimationStatus);
    _controller.dispose();
    _stateController.dispose();
    super.dispose();
  }

  /// Phase 32 PR 32d — emit `post_session_cinematic_shown` once on mount
  /// plus one `title_unlocked` per [TitleUnlockEvent] in the queue.
  ///
  /// Both events read from [widget.params.queueResult] — the same source
  /// the cinematic + summary panel render against — so the analytics
  /// payload matches what the user actually sees.
  ///
  /// `sagaNumber` (current finished workout count) is used as
  /// `title_unlocked.workout_number`: the title was unlocked AT this
  /// session, so the saga number IS the workout number.
  ///
  /// Defensive guards:
  ///   * `_analyticsFired` — Riverpod rebuilds + hot-reload safety.
  ///   * Missing user id (logged-out edge) → silent no-op.
  ///   * Analytics insert errors swallowed inside [AnalyticsRepository].
  ///   * Whole-body try/catch — [analyticsRepositoryProvider] reads
  ///     `Supabase.instance.client` eagerly; if that throws (test harness
  ///     without override, or a partial bootstrap failure) the failure must
  ///     not propagate into the post-frame callback and break the
  ///     cinematic. The "analytics must never break the user's flow"
  ///     contract applies at the call site.
  void _fireMountAnalytics() {
    if (_analyticsFired) return;
    _analyticsFired = true;
    try {
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) return;
      final analyticsRepo = ref.read(analyticsRepositoryProvider);
      final state = _stateController.state;
      final queue = state.queueResult.queue;
      final platform = currentPlatform();
      final appVersion = currentAppVersion();

      unawaited(
        analyticsRepo.insertEvent(
          userId: userId,
          event: AnalyticsEvent.postSessionCinematicShown(
            totalXp: state.totalXpEarned,
            hadRankUp: queue.any((e) => e is RankUpEvent),
            hadTitleUnlock: queue.any((e) => e is TitleUnlockEvent),
            hadClassChange: queue.any((e) => e is ClassChangeEvent),
          ),
          platform: platform,
          appVersion: appVersion,
        ),
      );

      for (final event in queue.whereType<TitleUnlockEvent>()) {
        unawaited(
          analyticsRepo.insertEvent(
            userId: userId,
            event: AnalyticsEvent.titleUnlocked(
              titleSlug: event.slug,
              workoutNumber: state.sagaNumber,
            ),
            platform: platform,
            appVersion: appVersion,
          ),
        );
      }
    } catch (_) {
      // Analytics is fire-and-forget — a missing repo / Supabase-not-init
      // edge must not break the cinematic playback.
    }
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
      // Multi-PR variant carries N pill-rows that stagger inside the
      // gold-flood window (200ms each), so its hold floor is higher than
      // the single-PR variant. Predicate `pillRows.isNotEmpty` mirrors the
      // `isMulti` check in `_buildPrCut` — timing branch and rendering
      // branch agree by construction.
      B3PrCut(:final pillRows) =>
        PostSessionTiming.b3PrWhiteFlash +
            (pillRows.isNotEmpty
                ? PostSessionTiming.b3HoldPrMulti
                : PostSessionTiming.b3HoldPr),
      B3TitleCut() => PostSessionTiming.b3HoldTitle,
      B3ClassChangeCut() => PostSessionTiming.b3HoldClassChange,
    };
  }

  void _handleTap() {
    if (_stateController.state.showSummary) return;
    // PR 30a UX pass — first tap retires the tap-hint affordance.
    // `setState` is needed because the host build composes the hint via
    // the `_userHasTapped` predicate; mutating without rebuilding would
    // leave the chevron pulsing after the gesture was confirmed.
    if (!_userHasTapped) {
      setState(() => _userHasTapped = true);
    }
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
      // Phase 31 round-2 Bug E — intercept the Android system back gesture
      // (predictive-back on targetSdk ≥ 34) so an accidental back-swipe
      // doesn't finish the FlutterActivity → exit the app. The post-session
      // route is push-only and there is NO re-entry path — once dismissed,
      // the cinematic + debrief are gone for that session. Block the pop
      // unconditionally, then show a confirmation dialog. Tapping LEAVE
      // routes through the same [onContinue] callback CONTINUAR uses, so
      // the route container (GoRouter) owns the actual nav (Decoupling
      // Rule 8 preserved).
      //
      // This route is a top-level GoRoute, NOT inside the shell's nested
      // navigator, so cluster `nested-nav-back-gate` does not apply — a
      // single PopScope is sufficient.
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final shouldLeave = await _showLeaveConfirmDialog(context, l10n);
          if (shouldLeave == true && context.mounted) {
            // Same path as CONTINUAR — controller cleanup + route exit.
            _stateController.onContinue();
            widget.onContinue();
          }
        },
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
      ),
    );
  }

  /// Phase 31 round-2 Bug E — confirmation dialog shown when the user
  /// presses the system back button. Returns `true` if the user confirms
  /// leaving; `false` (or `null` on outside-tap dismiss) keeps the screen.
  Future<bool?> _showLeaveConfirmDialog(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface2,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: Text(
            l10n.postSessionLeaveTitle,
            style: AppTextStyles.title.copyWith(color: AppColors.textCream),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                l10n.postSessionLeaveCancel.toUpperCase(),
                style: AppTextStyles.label.copyWith(
                  fontSize: 13,
                  letterSpacing: 0.16 * 13,
                  color: AppColors.textDim,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryViolet,
                foregroundColor: AppColors.textCream,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                l10n.postSessionLeaveConfirm.toUpperCase(),
                style: AppTextStyles.label.copyWith(
                  fontSize: 13,
                  letterSpacing: 0.16 * 13,
                  color: AppColors.textCream,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCinematic(PostSessionState state, AppLocalizations l10n) {
    final cut = state.cuts[state.cutIndex];
    // PR 30a UX pass — tap-hint visibility composes three predicates:
    //   * `!_userHasTapped`        — retires permanently on first tap
    //   * `state.cutIndex == 0`    — only ever visible during B1
    //   * `!_tapHintExpired`       — 2000ms one-shot timer (initState)
    // All three predicates are owned by THIS state — the hint widget is
    // pure render, the screen decides when to mount it. The skip button
    // is unconditionally present during all cinematic cuts.
    final showTapHint =
        !_userHasTapped && state.cutIndex == 0 && !_tapHintExpired;
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: Duration.zero,
          child: KeyedSubtree(
            key: ValueKey(state.cutIndex),
            child: _buildCut(cut, state, l10n),
          ),
        ),
        if (showTapHint) const CinematicTapHint(),
        CinematicSkipButton(
          label: l10n.cinematicSkipLabel,
          onSkip: () {
            _controller.stop();
            _stateController.skipToSummary();
          },
        ),
      ],
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
          // PR 32g (Bug 3) — surface RPC errors as a localized snackbar.
          // Pre-fix the closure had no try/catch, so the row's `rethrow`
          // became an unhandled Future rejection: the button reset to its
          // idle state but the user got no feedback. The row's contract is
          // "screen layer surfaces error snackbars" (see title_equip_row.dart
          // L76) — this fulfills that.
          try {
            final repo = ref.read(titlesRepositoryProvider);
            await repo.equipTitle(slug);
            ref.invalidate(earnedTitlesProvider);
            ref.invalidate(equippedTitleSlugProvider);
          } catch (_) {
            // `mounted` is the State's mounted flag (this closure runs on
            // the State, see `_buildSummary`). Guards against the user
            // navigating away mid-RPC. The analyzer's
            // `use_build_context_synchronously` lint is satisfied by
            // checking `mounted` (not `context.mounted`) before reading
            // `context`. If the widget has been unmounted, swallow:
            // there's no row left to reset and no surface to snack on, and
            // rethrowing into a dead closure produces an unhandled async
            // rejection — the exact symptom this fix was eliminating.
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.postSessionTitleEquipFailed)),
            );
            rethrow;
          }
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

    // Build the share-card payload + localized strings only when the
    // CTA is visible. Building them unconditionally would pull the
    // character class slug + per-BP labels into baseline-tier renders
    // for no reason.
    SharePayload? sharePayload;
    ShareCardStrings? shareCardStrings;
    ShareLocalizations? shareLocalizations;
    if (state.hasShareCta) {
      final classSlug =
          ref.read(characterClassProvider)?.slug ??
          CharacterClass.initiate.slug;
      // Phase 31 Pass 1 — read the persisted deltas + ranks directly from
      // state. Pre-Pass-1 the screen synthesized a single-entry deltas map
      // from the dominant BP because the controller didn't persist the
      // raw maps; the share factory then re-derived the dominant BP from
      // that 1-entry map (the same BP it started from — round-trip). Now
      // the state carries the full maps, so the factory's dominant-BP
      // selection sees every BP that actually earned XP and ranks accent
      // / hue fidelity matches the cinematic exactly.
      sharePayload = SharePayload.fromPostSessionState(
        tier: state.tier,
        queueResult: state.queueResult,
        prResult: state.prResult,
        bpXpDeltas: state.bpXpDeltas,
        bpRankAfter: state.bpRankAfter,
        bpProgressFractionAfter: state.bpProgressFractionAfter,
        exerciseNames: state.exerciseNames,
        totalXp: state.totalXpEarned,
        characterClassSlug: classSlug,
      );
      shareLocalizations = ShareLocalizations.from(l10n);
      shareCardStrings = _buildShareCardStrings(
        payload: sharePayload,
        state: state,
        l10n: l10n,
      );
    }

    // Build the S2 Mission Debrief section (Phase 31 Pass 3). The
    // section subsumes the legacy nextStepHook block on the panel — the
    // panel hides its eyebrow + hook when `debriefSection` is non-null.
    //
    // Phase 31 round-2 Bug F — resolve the character class to the
    // localized display name so the XP hero block can render
    // "+340 XP EARNED · IRON SENTINEL" as its right-side accent. Initiate
    // (the day-zero placeholder) collapses to `null` so the accent
    // omits cleanly — the mockup spec'd the right column as the
    // class-identity slot, not a generic forever-rendered chip.
    final classForDebrief = ref.read(characterClassProvider);
    final classLabel = classForDebrief == null
        ? null
        : (classForDebrief == CharacterClass.initiate
              ? null
              : localizedClassCopy(classForDebrief, l10n).name);
    final debriefSection = MissionDebriefSection(
      state: state,
      localizations: MissionDebriefLocalizations.from(l10n),
      classLabel: classLabel,
    );

    return PostSessionSummaryPanel(
      sagaLabel: sagaLabel,
      durationSetsLabel: durationSets,
      tonnageLabel: tonnage,
      nextStepEyebrow: l10n.summaryNextStepLabel,
      nextStepHook: hook,
      nextStepEyebrowColor: eyebrowColor,
      continueLabel: l10n.summaryContinueCta,
      shareLabel: l10n.summaryShareCta,
      sharePayload: sharePayload,
      shareCardStrings: shareCardStrings,
      shareLocalizations: shareLocalizations,
      hasShareCta: state.hasShareCta,
      titleEquipRow: titleRow,
      rankUpOverflow: overflowRow,
      debriefSection: debriefSection,
      onContinue: () {
        _stateController.onContinue();
        widget.onContinue();
      },
      nextStepHookFormatter: (h) => _formatHook(h, state, l10n),
    );
  }

  /// Compose the [ShareCardStrings] bundle from the post-session state
  /// snapshot + the active [AppLocalizations]. Mirrors the per-variant
  /// copy specs in mockup §6 D3 — Achievement Frame top + bottom collars,
  /// Discreet flood-and-slash.
  ///
  /// Kept inside the screen so the cinematic + share card pull from the
  /// same `state.bodyPartLabels` / `state.exerciseNames` maps the
  /// controller already resolved. Adding a separate composer would
  /// duplicate the lookups.
  ShareCardStrings _buildShareCardStrings({
    required SharePayload payload,
    required PostSessionState state,
    required AppLocalizations l10n,
  }) {
    final xpText = '+${state.totalXpEarned} XP';
    final bp = state.dominantBodyPart;
    final bpLabel = bp == null ? '' : (state.bodyPartLabels[bp] ?? bp.dbValue);
    final rank = payload.dominantBodyPartRank;
    final classSlug = payload.characterClassSlug;
    final className = classSlug.toUpperCase();
    final pr = payload.pr;
    // Achievement Frame top-collar saga eyebrow: dropped on class-change
    // sessions (Q4 lock — top collar reads NEW class name only when the
    // class boundary fires). Otherwise renders the current saga number.
    final sagaEyebrow = payload.isClassChange
        ? null
        : 'SAGA ${state.sagaNumber}';
    // Achievement Frame bottom-collar lift detail: "{weight}kg × {reps}
    // · {exerciseName}" on PR sessions (rendered heroGold); collapses
    // entirely on non-PR sessions.
    final liftDetail = pr == null
        ? null
        : '${pr.weightKg.toStringAsFixed(0)}kg × ${pr.reps} · ${pr.exerciseName}';
    final bpRank = bpLabel.isEmpty || rank == null
        ? bpLabel
        : '$bpLabel · Rank $rank';
    // Discreet eyebrow + d-hero keep their existing copy rules.
    final discreetEyebrow = payload.isClassChange
        ? '$className DESPERTOU.'
        : bpRank;
    final discreetHero = payload.isClassChange
        ? className
        : '+${state.totalXpEarned}';
    final discreetPrLine = pr == null
        ? null
        : '!! ${pr.weightKg.toStringAsFixed(0)}kg × ${pr.reps}';
    final discreetPrDetail = pr == null ? null : '${pr.exerciseName} · PR';

    return ShareCardStrings(
      wordmark: l10n.shareWordmark,
      achievementFrameClassName: className,
      achievementFrameSagaEyebrow: sagaEyebrow,
      achievementFrameXpHero: xpText,
      achievementFrameLiftDetail: liftDetail,
      achievementFrameHasPr: pr != null,
      achievementFrameBpRank: bpRank,
      discreetEyebrow: discreetEyebrow,
      discreetHero: discreetHero,
      discreetHeroSubLabel: 'XP',
      discreetPrLine: discreetPrLine,
      discreetPrDetail: discreetPrDetail,
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
