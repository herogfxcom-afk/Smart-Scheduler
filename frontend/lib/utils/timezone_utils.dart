import 'package:timezone/timezone.dart' as tz;
import 'js_stub.dart' if (dart.library.js_interop) 'dart:js_interop';
import 'js_stub.dart' if (dart.library.js_interop) 'dart:js_interop_unsafe';

/// Returns the user's timezone offset in hours
double getUserTzOffset() {
  try {
    final jsOffset = globalContext['userTzOffset'];
    if (jsOffset != null) {
      if (jsOffset is JSNumber) return jsOffset.toDartDouble;
    }
  } catch (_) {}
  
  return DateTime.now().timeZoneOffset.inMinutes / 60.0;
}

DateTime toUserLocal(DateTime utcDateTime) {
  // Ensure we are working with UTC source
  final utc = utcDateTime.isUtc ? utcDateTime : utcDateTime.toUtc();
  
  // For display purposes, toLocal() is the most robust way to get current browser time
  // It handles DST and local offsets automatically without relying on external timezone data
  return utc.toLocal();
}

/// The current time in user's local timeline (ignoring system UTC settings, purely local time representation)
DateTime userNow() {
  return toUserLocal(DateTime.now().toUtc());
}

/// Converts a locally selected wall-clock DateTime into a strict UTC DateTime 
/// for sending to the backend
DateTime fromUserLocal(DateTime localDateTime) {
  try {
    final location = tz.getLocation(getUserTimezone());
    final localTzDateTime = tz.TZDateTime(
      location,
      localDateTime.year,
      localDateTime.month,
      localDateTime.day,
      localDateTime.hour,
      localDateTime.minute,
      localDateTime.second,
    );
    return localTzDateTime.toUtc();
  } catch (e) {
    // Fallback if location not found
    return localDateTime.toUtc();
  }
}

String getUserTimezone() {
  try {
    final jsTz = globalContext['userTimezone'];
    if (jsTz != null && jsTz is JSString) {
      final detected = jsTz.toDart;
      if (detected.isNotEmpty) return detected;
    }
    
    // Fallback to tz.local if initialized
    final name = tz.local.name;
    if (name != 'UTC' && name != 'local') return name;
    
    return 'UTC';
  } catch (_) {
    return 'UTC';
  }
}

