import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../profile/providers/profile_providers.dart';

/// Top-of-home greeting (Phase 27 L2).
///
/// Renders two stacked lines:
///
///   1. Eyebrow — uppercased `weekday · short month-day`, locale-formatted
///      via [DateFormat.EEEE] + [DateFormat.MMMd]. Locale is sourced from
///      [AppLocalizations.localeName] so the eyebrow matches the rest of
///      the app's date rendering (same pattern used by
///      `WeekdayFormatter.shortDayLabel` in `core/utils/weekday_formatter.dart`
///      and `resume_workout_dialog`).
///   2. Name — the user's display name, with email-prefix fallback when
///      [Profile.displayName] is null/empty, then empty string when neither
///      source resolves.
///
/// **Why the date isn't an ARB key.** `intl`'s locale-aware formatters
/// produce the right output for both `en` and `pt-BR` (weekday + short
/// month-day) without any string templating on our side. The middle-dot
/// separator (` · `) is locale-neutral. Adding an ARB key would only
/// duplicate what `intl` already does correctly.
///
/// **Name fallback chain.** `displayName` (trimmed, non-empty) → email
/// prefix (left of `@`) → empty string. The empty-string terminal is
/// deliberate: if both sources are missing the widget renders an empty
/// name slot rather than a generic "User" or "Guest" placeholder. This
/// avoids inventing copy without an ARB key and matches the locked
/// 2026-05-18 decision to source the name from `profileProvider`.
///
/// **Why `clock.now()`.** Tests pin a fixed reference time via
/// `withClock(Clock.fixed(...))` — the same pattern `streakProvider` uses.
/// Using the ambient clock keeps the date-formatting test deterministic
/// without forcing the widget to take a `DateTime` constructor arg.
///
/// **L10n strategy.** This widget is single-use on the Home screen (no
/// reuse surface), so it reads [AppLocalizations.of] directly — same
/// pattern as [EncouragementNudge]. Per
/// `feedback_widget_l10n_parameterization`, reusable widgets should take
/// localized strings as constructor params; one-shot screen-bound widgets
/// can read l10n inline.
class HomeGreeting extends ConsumerWidget {
  const HomeGreeting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = l10n.localeName;
    final now = clock.now();
    final dateLabel = _formatDate(now, locale);

    final profile = ref.watch(profileProvider).value;
    final email = ref.watch(currentUserEmailProvider);
    final name = _resolveName(profile?.displayName, email);

    return Semantics(
      // `container: true` + `explicitChildNodes: true` keeps the identifier
      // reachable on Flutter web's AOM — see
      // `cluster_semantics_identifier_pair_rule`. Future E2E selectors can
      // hook on `home-greeting` without grepping localized text.
      container: true,
      explicitChildNodes: true,
      identifier: 'home-greeting',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              dateLabel,
              style: AppTextStyles.label.copyWith(
                fontSize: 10,
                letterSpacing: 0.16 * 10,
                // Phase 38.9 T2.6: AA dim eyebrow (textDim ~6.62:1 nominal but
                // renders ~2.78:1 at 10sp; textDimAA clears the floor rendered).
                color: AppColors.textDimAA,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              name,
              style: AppTextStyles.headline.copyWith(
                fontSize: 22,
                color: AppColors.textCream,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the eyebrow string: uppercased `weekday · short month-day`.
  ///
  /// Examples:
  ///   * en + Tue May 19 → `"TUESDAY · MAY 19"`
  ///   * pt + Tue May 19 → `"TERÇA-FEIRA · 19 DE MAI."`
  String _formatDate(DateTime now, String locale) {
    final weekday = DateFormat.EEEE(locale).format(now);
    final monthDay = DateFormat.MMMd(locale).format(now);
    return '$weekday · $monthDay'.toUpperCase();
  }

  /// Resolves the rendered name from the two upstream sources.
  ///
  /// Returns `displayName` (trimmed) when non-empty, else the email's
  /// local-part (left of `@`), else an empty string. Whitespace-only
  /// `displayName` is treated as empty so users who entered " " during
  /// onboarding don't get a blank name on Home.
  String _resolveName(String? displayName, String? email) {
    final trimmed = displayName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    if (email == null || email.isEmpty) return '';
    final prefix = email.split('@').first;
    return prefix;
  }
}
