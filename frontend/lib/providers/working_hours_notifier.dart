import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import '../models/availability.dart';
import '../utils/timezone_utils.dart';
import 'package:timezone/timezone.dart' as tz;

class WorkingHoursNotifier extends ChangeNotifier {
  // Use a generic GlobalKey to avoid potential SfCalendarState type errors during build
  final GlobalKey calendarKey = GlobalKey();

  List<TimeRegion> buildRegions(List<Availability> availability) {
    if (availability.isEmpty) return [];
    
    final List<TimeRegion> regions = [];
    try {
      final location = tz.getLocation(getUserTimezone());
      final now = userNow();
      
      // Build regions for a reasonable range around today
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
    // Dynamic cast to access refresh() if available on the state
    try {
      (calendarKey.currentState as dynamic)?.refresh();
    } catch (e) {
      debugPrint("Could not call refresh on calendar: $e");
    }
    notifyListeners();
  }
}
