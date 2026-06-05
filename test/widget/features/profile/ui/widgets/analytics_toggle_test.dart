import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/analytics/data/analytics_repository.dart';
import 'package:repsaga/features/profile/providers/analytics_enabled_provider.dart';
import 'package:repsaga/features/profile/ui/widgets/analytics_toggle.dart';

import '../../../../../helpers/test_material_app.dart';

/// In-memory stub Notifier for the widget tests — sidesteps Hive disk
/// I/O. The persisted-Hive contract is covered by the provider unit
/// test (`analytics_enabled_provider_test.dart`); these widget tests
/// only need to assert that the toggle UI mirrors the notifier value
/// and flips it on tap.
class _StubNotifier extends Notifier<bool>
    with Mock
    implements AnalyticsEnabledNotifier {
  _StubNotifier(this._initial);
  final bool _initial;

  @override
  bool build() {
    AnalyticsRepository.setEnabled(_initial);
    return _initial;
  }

  @override
  Future<void> setEnabled(bool value) async {
    AnalyticsRepository.setEnabled(value);
    state = value;
  }
}

void main() {
  setUp(() {
    AnalyticsRepository.debugResetEnabled();
  });

  Widget buildHost({bool initial = true}) {
    return ProviderScope(
      overrides: [
        analyticsEnabledProvider.overrideWith(() => _StubNotifier(initial)),
      ],
      child: TestMaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: AnalyticsToggle()),
      ),
    );
  }

  testWidgets('renders title and subtitle', (tester) async {
    await tester.pumpWidget(buildHost());

    expect(find.text('Send usage analytics'), findsOneWidget);
    expect(
      find.text('Helps RepSaga improve. You can disable any time.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'switch reflects the persisted value (true by default — opt-out model)',
    (tester) async {
      await tester.pumpWidget(buildHost(initial: true));

      expect(tester.widget<Switch>(find.byType(Switch)).value, true);
    },
  );

  testWidgets('tapping the switch flips the visible position from on to off', (
    tester,
  ) async {
    await tester.pumpWidget(buildHost(initial: true));

    expect(tester.widget<Switch>(find.byType(Switch)).value, true);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();

    expect(tester.widget<Switch>(find.byType(Switch)).value, false);
  });

  testWidgets(
    'flipping the switch off propagates to AnalyticsRepository.isEnabled (analytics writes gated)',
    (tester) async {
      await tester.pumpWidget(buildHost(initial: true));

      expect(AnalyticsRepository.isEnabled, true);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      // Subsystem gate flipped — this is the user-visible side effect
      // (the analytics_events table will no longer receive writes).
      expect(AnalyticsRepository.isEnabled, false);
    },
  );

  testWidgets(
    'a persisted opt-out (false) renders as an OFF switch on first build',
    (tester) async {
      await tester.pumpWidget(buildHost(initial: false));

      expect(tester.widget<Switch>(find.byType(Switch)).value, false);
    },
  );

  testWidgets('flipping ON re-enables the AnalyticsRepository gate', (
    tester,
  ) async {
    await tester.pumpWidget(buildHost(initial: false));

    // Build with persisted false should have synced the static gate.
    expect(AnalyticsRepository.isEnabled, false);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();

    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
    expect(AnalyticsRepository.isEnabled, true);
  });
}
