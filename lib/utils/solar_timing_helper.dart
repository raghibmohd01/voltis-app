/// Helper to determine daytime solar production windows,
/// taking into consideration seasonal daylight differences (e.g., Winter season).
class SolarTimingHelper {
  /// Returns whether the date falls within the winter solar season.
  /// In the Northern Hemisphere (India), winter solar hours apply from
  /// late October through February.
  static bool isWinterSeason([DateTime? now]) {
    final date = now ?? DateTime.now();
    return date.month >= 11 || date.month <= 2 || (date.month == 10 && date.day >= 15);
  }

  /// Returns the start and end minutes of the day (0..1439) for guaranteed solar production.
  ///
  /// - Winter season core peak: 10:00 AM to 3:30 PM (600 min to 930 min)
  ///   (Morning fog burns off after 9:30 AM, sun angle drops steeply by 3:30 PM)
  /// - Standard / Summer: 9:00 AM to 4:00 PM (540 min to 960 min)
  static ({int startMinutes, int endMinutes, String label}) getDaytimeRange([DateTime? now]) {
    final isWinter = isWinterSeason(now);
    if (isWinter) {
      return (
        startMinutes: 9 * 60 + 30, // 9:30 AM
        endMinutes: 15 * 60 + 30,  // 3:30 PM
        label: '9:30 AM – 3:30 PM (Winter)',
      );
    } else {
      return (
        startMinutes: 9 * 60,      // 9:00 AM
        endMinutes: 16 * 60,       // 4:00 PM
        label: '9:00 AM – 4:00 PM',
      );
    }
  }

  /// Returns true if [dt] is within strong daytime solar hours in local time.
  static bool isDaytimeSolarHours([DateTime? dt]) {
    final date = (dt ?? DateTime.now()).toLocal();
    final minuteOfDay = date.hour * 60 + date.minute;
    final range = getDaytimeRange(date);
    return minuteOfDay >= range.startMinutes && minuteOfDay <= range.endMinutes;
  }
}

