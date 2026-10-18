import 'package:flutter_test/flutter_test.dart';
import 'package:inverter_dashboard/utils/solar_timing_helper.dart';

void main() {
  group('SolarTimingHelper Tests', () {
    test('Winter Season detection (November through February and late October)', () {
      expect(SolarTimingHelper.isWinterSeason(DateTime(2026, 12, 15, 12, 0)), isTrue);
      expect(SolarTimingHelper.isWinterSeason(DateTime(2026, 1, 10, 12, 0)), isTrue);
      expect(SolarTimingHelper.isWinterSeason(DateTime(2026, 2, 20, 12, 0)), isTrue);
      expect(SolarTimingHelper.isWinterSeason(DateTime(2026, 10, 25, 12, 0)), isTrue);
      expect(SolarTimingHelper.isWinterSeason(DateTime(2026, 6, 15, 12, 0)), isFalse);
    });

    test('Winter daytime hours: 9:30 AM to 3:30 PM', () {
      final winterDate = DateTime(2026, 12, 1, 11, 0); // 11:00 AM
      expect(SolarTimingHelper.isDaytimeSolarHours(winterDate), isTrue);

      final winterMorningEarly = DateTime(2026, 12, 1, 9, 15); // 9:15 AM (before 9:30 AM)
      expect(SolarTimingHelper.isDaytimeSolarHours(winterMorningEarly), isFalse);

      final winterEveningLate = DateTime(2026, 12, 1, 15, 45); // 3:45 PM (after 3:30 PM)
      expect(SolarTimingHelper.isDaytimeSolarHours(winterEveningLate), isFalse);

      final winterPeakMidday = DateTime(2026, 12, 1, 14, 0); // 2:00 PM
      expect(SolarTimingHelper.isDaytimeSolarHours(winterPeakMidday), isTrue);
    });

    test('Summer daytime hours: 9:00 AM to 4:00 PM', () {
      final summerEarly = DateTime(2026, 6, 1, 9, 15); // 9:15 AM
      expect(SolarTimingHelper.isDaytimeSolarHours(summerEarly), isTrue);

      final summerLate = DateTime(2026, 6, 1, 15, 50); // 3:50 PM
      expect(SolarTimingHelper.isDaytimeSolarHours(summerLate), isTrue);

      final summerPast = DateTime(2026, 6, 1, 16, 10); // 4:10 PM
      expect(SolarTimingHelper.isDaytimeSolarHours(summerPast), isFalse);
    });
  });
}
