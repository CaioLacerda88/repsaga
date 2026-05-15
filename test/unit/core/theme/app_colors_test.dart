import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';

void main() {
  group('AppColors body-part tokens (Phase 26a)', () {
    test('bodyPartChest is Tailwind Pink 400 (#F472B6)', () {
      expect(AppColors.bodyPartChest, const Color(0xFFF472B6));
    });

    test('bodyPartBack is Tailwind Sky 400 (#38BDF8)', () {
      expect(AppColors.bodyPartBack, const Color(0xFF38BDF8));
    });

    test('bodyPartCardio is Tailwind Orange 400 (#FB923C)', () {
      expect(AppColors.bodyPartCardio, const Color(0xFFFB923C));
    });
  });

  group('AppColors progress infrastructure (Phase 26a)', () {
    test('xpTrack is violet-tinted 10% alpha (#1AB36DFF)', () {
      // 0x1AB36DFF: 10% alpha (0x1A = 26 ≈ 10.2% of 255) on the
      // hotViolet base color (#B36DFF). Replaces the rgba(255,255,255,0.06)
      // neutral white-alpha track currently used across XP/progress bars.
      expect(AppColors.xpTrack, const Color(0x1AB36DFF));
    });
  });
}
