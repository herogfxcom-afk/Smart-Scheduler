import 'package:timezone/timezone.dart' as tz;
import 'js_stub.dart' if (dart.library.js_interop) 'dart:js_interop';
import 'js_stub.dart' if (dart.library.js_interop) 'dart:js_interop_unsafe';

/// Returns the user's timezone offset in hours
double getUserTzOffset() {
  try {
    final jsOffset = globalContext['userTzOffset'];
    if (jsOffset != null) {
      return (jsOffset as JSNumber).toDartDouble;
    }
  } catch (_) {}
  
  // Also fallback to the formal location
  final now = tz.TZDateTime.now(tz.local);
  return now.timeZoneOffset.inMinutes / 60.0;
}

/// Converts a UTC DateTime received from the backend into the user's local clock time representations
DateTime toUserLocal(DateTime utcDateTime) {
  // Ensure we are working with UTC source
  final utc = utcDateTime.isUtc ? utcDateTime : utcDateTime.toUtc();
  // We use TZDateTime to get the strict local representation
  final localTzDateTime = tz.TZDateTime.from(utc, tz.local);
  return DateTime(
    localTzDateTime.year,
    localTzDateTime.month,
    localTzDateTime.day,
    localTzDateTime.hour,
    localTzDateTime.minute,
    localTzDateTime.second,
  );
}

/// The current time in user's local timeline (ignoring system UTC settings, purely local time representation)
DateTime userNow() {
  return toUserLocal(DateTime.now().toUtc());
}

/// Converts a locally selected wall-clock DateTime into a strict UTC DateTime 
/// for sending to the backend
DateTime fromUserLocal(DateTime localDateTime) {
  // We treat the passed localDateTime as if it happened in tz.local
  final localTzDateTime = tz.TZDateTime(
    tz.local,
    localDateTime.year,
    localDateTime.month,
    localDateTime.day,
    localDateTime.hour,
    localDateTime.minute,
    localDateTime.second,
  );
  return localTzDateTime.toUtc();
}

String getUserTimezone() {
  try {
    return tz.local.name;
  } catch (_) {
    return 'UTC';
  }
}

