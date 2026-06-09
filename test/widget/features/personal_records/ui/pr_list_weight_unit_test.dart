import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/personal_records/models/personal_record.dart';
import 'package:repsaga/features/personal_records/models/record_type.dart';
import 'package:repsaga/features/personal_records/providers/pr_providers.dart';
import 'package:repsaga/features/personal_records/ui/pr_list_screen.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import '../../../../helpers/test_material_app.dart';

void main() {
  group('PRListScreen weight unit display (PO-030)', () {
    testWidgets('displays weight unit from profile (lbs)', (tester) async {
      final records = [
        (
          record: PersonalRecord(
            id: 'pr-1',
            userId: 'user-001',
            exerciseId: 'ex-1',
            recordType: RecordType.maxWeight,
            value: 100,
            achievedAt: DateTime(2026),
          ),
          exerciseName: 'Bench Press',
          equipmentType: EquipmentType.barbell,
        ),
        (
          record: PersonalRecord(
            id: 'pr-2',
            userId: 'user-001',
            exerciseId: 'ex-1',
            recordType: RecordType.maxVolume,
            value: 3000,
            achievedAt: DateTime(2026),
          ),
          exerciseName: 'Bench Press',
          equipmentType: EquipmentType.barbell,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            prListWithExercisesProvider.overrideWith(
              (ref) => Future.value(records),
            ),
            profileProvider.overrideWith(() => _FakeProfileNotifier('lbs')),
          ],
          child: TestMaterialApp(
            theme: AppTheme.dark,
            home: const PRListScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Volume should show "lbs" not "kg"
      expect(find.text('100 lbs'), findsOneWidget);
      expect(find.text('3000 lbs'), findsOneWidget);
      expect(find.textContaining('kg'), findsNothing);
    });

    testWidgets('displays reps without unit suffix', (tester) async {
      final records = [
        (
          record: PersonalRecord(
            id: 'pr-1',
            userId: 'user-001',
            exerciseId: 'ex-1',
            recordType: RecordType.maxReps,
            value: 12,
            achievedAt: DateTime(2026),
          ),
          exerciseName: 'Pull-ups',
          equipmentType: EquipmentType.bodyweight,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            prListWithExercisesProvider.overrideWith(
              (ref) => Future.value(records),
            ),
            profileProvider.overrideWith(() => _FakeProfileNotifier('kg')),
          ],
          child: TestMaterialApp(
            theme: AppTheme.dark,
            home: const PRListScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('12 reps'), findsOneWidget);
    });
  });
}

class _FakeProfileNotifier extends AsyncNotifier<Profile?>
    implements ProfileNotifier {
  _FakeProfileNotifier(this._unit);

  final String _unit;

  @override
  Future<Profile?> build() async {
    return Profile(id: 'user-001', weightUnit: _unit);
  }

  @override
  Future<void> saveOnboardingProfile({
    required String fitnessLevel,
    int trainingFrequencyPerWeek = 3,
  }) async {}

  @override
  Future<void> updateTrainingFrequency(int frequency) async {}

  @override
  Future<void> toggleWeightUnit() async {}
}
