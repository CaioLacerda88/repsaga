import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/device/platform_info.dart';
import 'core/local_storage/hive_service.dart';
import 'core/observability/sentry_init.dart';
import 'core/observability/sentry_report.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Phase 27 L14: lock `google_fonts` to never network-fetch. Both Rajdhani
  // and Inter are bundled via `pubspec.yaml > flutter.fonts:` and read via
  // direct `TextStyle(fontFamily: ...)` calls (see [AppTextStyles]). The
  // package is kept as a transitive dep but no code path in `lib/` should
  // call `GoogleFonts.*` — `AppTextStyles` is the only sanctioned entry
  // point. If a future caller introduces a `GoogleFonts.*` reference, this
  // lock makes the failure mode clear at debug time instead of silently
  // network-fetching (the silent-fetch race was the root cause of the
  // missing-Rajdhani-on-device bug surfaced during Phase 27 verification).
  GoogleFonts.config.allowRuntimeFetching = false;

  // Register the Game-Icons.net CC BY 3.0 attribution for the v3-silhouette
  // icon pack (AppIcons / AppMuscleIcons / AppEquipmentIcons). This makes
  // the credit surface through Flutter's built-in `showLicensePage`, which
  // satisfies the license's attribution requirement without us shipping a
  // dedicated credits screen. Registering here (pre-dotenv, pre-Supabase)
  // is safe because `LicenseRegistry.addLicense` only stores a generator
  // callback — nothing is enumerated until the license page is opened.
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Game-Icons.net'],
      'Some icons from game-icons.net, by Lorc and Delapouite, licensed '
      'under CC BY 3.0.\n\n'
      'https://creativecommons.org/licenses/by/3.0/',
    );
  });

  await dotenv.load();
  await const HiveService().init();
  await initAppVersion();

  // Seed the Sentry opt-out flag from Hive BEFORE init. If the user has
  // disabled crash reports in a prior session, we respect that immediately.
  final prefs = Hive.box(HiveService.userPrefs);
  final crashReportsEnabled =
      prefs.get('crash_reports_enabled', defaultValue: true) as bool;
  SentryReport.setEnabled(crashReportsEnabled);

  await initSentryAndRun(() async {
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    runApp(const ProviderScope(child: App()));
  });
}
