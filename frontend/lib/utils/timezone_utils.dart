import 'dart:js' as js;

double getUserTzOffset() {
  try {
    final offset = js.context['userTzOffset'];
    if (offset != null) return (offset as num).toDouble();
  } catch (_) {}
  // Fallback for mobile / if JS doesn't work
  return DateTime.now().timeZoneOffset.inMinutes / 60.0;
}

String getUserTimezone() {
  try {
    final tz = js.context['userTimezone'];
    if (tz != null) return tz.toString();
  } catch (_) {}
  return 'UTC';
}
