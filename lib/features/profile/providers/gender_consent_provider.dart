import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/local_storage/hive_service.dart';

const _hiveKey = 'gender_consent_enabled';

/// Notifier for the gender opt-in disclosure consent. Backed by the
/// `user_prefs` Hive box. Defaults to `false` — the gender editor
/// surfaces a one-time disclosure banner above the options the FIRST
/// time the user opens it (gender is sensitive data under LGPD Art. 11 /
/// Privacy Policy §7).
///
/// Flips to `true` when the user picks ANY value (including "Other"),
/// after which the banner self-extinguishes on subsequent opens.
/// Clearing the gender back to "Not set" does NOT flip this back to
/// `false` — the user has already seen the disclosure, so re-showing
/// would be noise. The Settings → Privacy section intentionally does
/// NOT carry a separate withdrawal toggle for gender (the editor's
/// "Not set" option IS the withdrawal mechanism — clearing the value
/// removes the sensitive datum from `profiles.gender`).
///
/// Cluster: `data-protection-compliance`.
class GenderConsentNotifier extends Notifier<bool> {
  @override
  bool build() {
    final box = Hive.box(HiveService.userPrefs);
    return box.get(_hiveKey, defaultValue: false) as bool;
  }

  Future<void> setEnabled(bool enabled) async {
    final box = Hive.box(HiveService.userPrefs);
    await box.put(_hiveKey, enabled);
    state = enabled;
  }
}

final genderConsentProvider = NotifierProvider<GenderConsentNotifier, bool>(
  GenderConsentNotifier.new,
);
