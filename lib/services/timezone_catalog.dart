import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

class TimezoneCatalog {
  TimezoneCatalog._();

  static bool _initialized = false;

  static void ensureInitialized() {
    if (_initialized) return;
    timezone_data.initializeTimeZones();
    _initialized = true;
  }

  static List<String> get names {
    ensureInitialized();
    final names = tz.timeZoneDatabase.locations.keys.toList(growable: false);
    names.sort();
    return names;
  }

  static String offsetLabel(String? timezone) {
    final date = localNow(timezone);
    if (date == null) return 'UTC';
    final offset = date.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final totalMinutes = offset.inMinutes.abs();
    final hours = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final minutes = (totalMinutes % 60).toString().padLeft(2, '0');
    return minutes == '00' ? 'UTC$sign$hours' : 'UTC$sign$hours:$minutes';
  }

  static String localTimeLabel(String? timezone) {
    final date = localNow(timezone);
    if (date == null) return '';
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute local time';
  }

  static tz.TZDateTime? localNow(String? timezone) {
    if (timezone == null || timezone.trim().isEmpty) return null;
    ensureInitialized();
    try {
      return tz.TZDateTime.now(tz.getLocation(timezone));
    } catch (_) {
      return null;
    }
  }
}
