import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/local_storage/hive_service.dart';

const _hiveKey = 'bodyweight_consent_enabled';

/// Notifier for the body-weight sensitive-data opt-in. Backed by the
/// `user_prefs` Hive box. Defaults to `false` — body weight is health
/// data under LGPD Art. 11 / GDPR Art. 9 and requires **explicit
/// opt-in** consent before any collection. This is the inverse of the
/// crash-reports / analytics defaults (those use opt-out under
/// "legitimate interest"; sensitive data cannot).
///
/// Cluster: `data-protection-compliance`. The dialog at the save site
/// reads this value to decide whether to surface the consent prompt;
/// the Profile → Settings → Privacy toggle is the withdrawal mechanism.
///
/// **Withdrawal semantics.** Flipping the toggle off does NOT delete the
/// stored `profiles.bodyweight_kg` value — that's an account-management
/// concern handled via the manage-data screen (`resetAllAccountData`).
/// Flipping off only prevents the editor from writing future values
/// without re-consent. This mirrors the documented behavior in
/// `bodyweightConsentToggleSubtitle`.
///
/// Unlike [CrashReportsEnabledNotifier], there is no runtime "subsystem
/// gate" — body weight is collected by an explicit user action (save tap)
/// rather than fired automatically. The consent dialog at the save site
/// is the gate; this provider's value is the persisted state of that gate.
class BodyweightConsentNotifier extends Notifier<bool> {
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

final bodyweightConsentProvider =
    NotifierProvider<BodyweightConsentNotifier, bool>(
      BodyweightConsentNotifier.new,
    );
