import 'dart:js_interop';
import 'dart:js_interop_unsafe';

double getUserTzOffset() {
  try {
    final jsOffset = globalContext['userTzOffset'];
    if (jsOffset != null) {
      return (jsOffset as JSNumber).toDartDouble;
    }
  } catch (_) {}
  return DateTime.now().timeZoneOffset.inMinutes / 60.0;
}

DateTime toUserLocal(DateTime utcDateTime) {
  final offsetHours = getUserTzOffset();
  // We assume the input is UTC and we add the offset to get the user's wall clock time
  return utcDateTime.toUtc().add(Duration(minutes: (offsetHours * 60).toInt()));
}

DateTime userNow() {
  return toUserLocal(DateTime.now().toUtc());
}

String getUserTimezone() {
  try {
    final jsTz = globalContext['userTimezone'];
    if (jsTz != null) return (jsTz as JSString).toDart;
  } catch (_) {}
  return 'UTC';
}
