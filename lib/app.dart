import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import 'core/constants/supported_locales.dart';
import 'core/l10n/locale_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_providers.dart';
import 'features/profile/providers/profile_providers.dart';
import 'l10n/app_localizations.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);

    // Reconcile locale after sign-in. Listen to auth state — NOT profileProvider —
    // because App mounts before login and subscribing to profileProvider here
    // would trigger ProfileNotifier.build() while currentUserId is still null,
    // caching AsyncData(null) that never refetches after sign-in.
    ref.listen(authStateProvider, (prev, next) {
      final event = next.value?.event;
      if (event != AuthChangeEvent.signedIn &&
          event != AuthChangeEvent.initialSession) {
        return;
      }
      if (next.value?.session == null) return;

      Future.microtask(() async {
        try {
          final profile = await ref.read(profileProvider.future);
          if (profile == null) return;
          await ref
              .read(localeProvider.notifier)
              .reconcileWithRemote(profile.locale);
        } catch (_) {
          // Best-effort: keep local Hive locale if remote lookup fails.
        }
      });
    });

    return MaterialApp.router(
      title: 'RepSaga',
      theme: AppTheme.dark,
      routerConfig: router,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // PR A2 — locale list lifted to `kSupportedLocales` so the Dart
      // hydration helper (`ProfileNotifier`) and the SQL migration
      // `00073_backfill_user_metadata_locale` share a single source of
      // truth with the MaterialApp registration. A unit test pins that
      // `kSupportedLocales` matches `AppLocalizations.supportedLocales`,
      // so the gen-l10n-produced list and the const can't drift even
      // though we no longer pass the gen list directly.
      supportedLocales: kSupportedLocales.map(Locale.new).toList(),
      debugShowCheckedModeBanner: false,
    );
  }
}
