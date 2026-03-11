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

String getUserTimezone() {
  try {
    final jsTz = globalContext['userTimezone'];
    if (jsTz != null) return (jsTz as JSString).toDart;
  } catch (_) {}
  return 'UTC';
}
