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
    // Don't notify here to avoid build-time loops. 
    // The versioned key change handles the refresh.
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
    try {
      if (_cachedRegions != null && _lastAvailability == _availability) {
        return _cachedRegions!;
      }

      final regions = <TimeRegion>[];
      tz.Location location;
      try {
        location = tz.getLocation(getUserTimezone());
      } catch (_) {
        location = tz.UTC;
      }
      
      final now = userNow();

      for (int i = -7; i <= 14; i++) {
        final base = now.add(Duration(days: i));
        final day = _getAvailabilityForDay(base.weekday);
        if (day == null) continue;

        try {
          final startParts = (day.startTime ?? "09:00").split(':');
          final endParts = (day.endTime ?? "18:00").split(':');
          
          if (startParts.length < 2 || endParts.length < 2) continue;

          final start = tz.TZDateTime(
            location, 
            base.year, 
            base.month, 
            base.day, 
            int.tryParse(startParts[0]) ?? 9, 
            int.tryParse(startParts[1]) ?? 0
          );
          
          final end = tz.TZDateTime(
            location, 
            base.year, 
            base.month, 
            base.day, 
            int.tryParse(endParts[0]) ?? 18, 
            int.tryParse(endParts[1]) ?? 0
          );

          regions.add(TimeRegion(
            startTime: start,
            endTime: end,
            color: Colors.green.withOpacity(0.25),
            enablePointerInteraction: false,
          ));
        } catch (e) {
          debugPrint("Error parsing time for region: $e");
          continue;
        }
      }

      _cachedRegions = regions;
      _lastAvailability = _availability;
      return regions;
    } catch (e) {
      debugPrint("Fatal error building regions: $e");
      return [];
    }
  }

  void forceRefresh() {
    _version++;
    _cachedRegions = null;
    notifyListeners();
  }
}
