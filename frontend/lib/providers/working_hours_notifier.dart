import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import '../models/availability.dart';
import '../utils/timezone_utils.dart';
import 'package:timezone/timezone.dart' as tz;

class WorkingHoursNotifier extends ChangeNotifier {
  // Syncfusion's SfCalendarState is private in recent versions, so GlobalKey<SfCalendarState> 
  // throws a compilation error. To achieve the exact same "deep clean" effect and fix the overlay bug,
  // we use a versioned ValueKey that completely destroys and recreates the calendar when settings change.
  int _version = 0;

  Key get calendarKey => ValueKey('working_hours_calendar_v$_version');

  List<TimeRegion> buildRegions(List<Availability> availability) {
    if (availability.isEmpty) return [];
    
    // We strictly return a completely NEW list every time to avoid structural equality caching
    final List<TimeRegion> regions = [];
    try {
      final location = tz.getLocation(getUserTimezone());
      final now = userNow();
      
      for (int i = -7; i <= 14; i++) {
        final base = now.add(Duration(days: i));
        final dayOfWeek = (base.weekday - 1); // 0-6
        
        final dayData = availability.firstWhere(
          (a) => a.dayOfWeek == dayOfWeek,
          orElse: () => availability[0],
        );

        if (!dayData.isEnabled) continue;

        final startParts = dayData.startTime.split(':');
        final endParts = dayData.endTime.split(':');
        
        final start = tz.TZDateTime(
          location,
          base.year,
          base.month,
          base.day,
          int.parse(startParts[0]),
          int.parse(startParts[1]),
        );
        
        final end = tz.TZDateTime(
          location,
          base.year,
          base.month,
          base.day,
          int.parse(endParts[0]),
          int.parse(endParts[1]),
        );

        regions.add(TimeRegion(
          startTime: start,
          endTime: end,
          enablePointerInteraction: true,
          color: Colors.green.withOpacity(0.12),
        ));
      }
    } catch (e) {
      debugPrint("Error building working regions: $e");
    }
    
    return regions;
  }

  void refresh() {
    // Incrementing the version changes the calendarKey, forcing Flutter to unmount the buggy
    // SfCalendar widget and build a fresh one, wiping all stale specialRegions from memory.
    _version++;
    notifyListeners();
  }
}
