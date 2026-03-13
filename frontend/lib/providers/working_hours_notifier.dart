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
      final dayOfWeek = (base.weekday - 1); // 0-6
      
      final dayData = _availability.firstWhere(
        (a) => a.dayOfWeek == dayOfWeek,
        orElse: () => _availability.isNotEmpty ? _availability[0] : Availability(dayOfWeek: dayOfWeek, startTime: '09:00', endTime: '18:00', isEnabled: false),
      );

      if (!dayData.isEnabled) continue;

      final startParts = dayData.startTime.split(':');
      final endParts = dayData.endTime.split(':');

      final start = tz.TZDateTime(location, base.year, base.month, base.day, int.parse(startParts[0]), int.parse(startParts[1]));
      final end   = tz.TZDateTime(location, base.year, base.month, base.day, int.parse(endParts[0]), int.parse(endParts[1]));

      regions.add(TimeRegion(
        startTime: start,
        endTime: end,
        color: Colors.green.withOpacity(0.25),
        enablePointerInteraction: false,
      ));
    }

    _cachedRegions = regions;
    _lastAvailability = _availability;
    return regions;
  }

  void forceRefresh() {
    _version++;
    _cachedRegions = null;
    notifyListeners();
  }
}
