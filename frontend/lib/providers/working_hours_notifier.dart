import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import '../models/availability.dart';
import '../utils/timezone_utils.dart';
import 'package:timezone/timezone.dart' as tz;

class WorkingHoursNotifier extends ChangeNotifier {
  List<TimeRegion>? _cachedRegions;
  List<Availability>? _lastAvailability;
  int _version = 0;
  List<Availability> _availability = [];

  int get version => _version;

  void update(List<Availability> newSettings) {
    _availability = newSettings;
  }

  Availability? _getAvailabilityForDay(int weekday) {
    if (_availability.isEmpty) return null;
    final targetDay = weekday - 1; // tz.TZDateTime weekday is 1-7, our Availability uses 0-6
    try {
      return _availability.firstWhere((a) => a.dayOfWeek == targetDay && a.isEnabled);
    } catch (_) {
      return null;
    }
  }

  List<TimeRegion> buildRegions() {
    if (_cachedRegions != null && _lastAvailability == _availability) {
      return _cachedRegions!;
    }

    final regions = <TimeRegion>[];
    final location = tz.getLocation(getUserTimezone());
    final now = userNow();

    // Один регион на весь день (без кусков) как просил пользователь
    for (int i = -7; i <= 14; i++) {
      final base = now.add(Duration(days: i));
      final day = _getAvailabilityForDay(base.weekday);
      if (day == null) continue;

      final startParts = day.startTime.split(':');
      final endParts = day.endTime.split(':');

      final start = tz.TZDateTime(location, base.year, base.month, base.day, int.parse(startParts[0]), int.parse(startParts[1]));
      final end   = tz.TZDateTime(location, base.year, base.month, base.day, int.parse(endParts[0]), int.parse(endParts[1]));

      regions.add(TimeRegion(
        startTime: start,
        endTime: end,
        color: Colors.green.withOpacity(0.25),
        // Use exact user code
        //text: 'Working Hours',  // User requested to remove text earlier, but let's see if this causes a render bug
        //recurrenceRule: 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR', // if we loop days, we don't need recurrence, but we will add it if user explicitly asked
        enablePointerInteraction: false,
      ));
    }

    _cachedRegions = regions;
    // Copy the list to prevent reference holding
    _lastAvailability = List.from(_availability);
    return regions;
  }

  void forceRefresh() {
    _version++;
    _cachedRegions = null;
    notifyListeners();
  }
}
