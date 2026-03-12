import 'package:url_launcher/url_launcher.dart';
import '../models/meeting.dart';
import 'package:intl/intl.dart';
import 'timezone_utils.dart'; // We use this to get the UTC start/end

class IcsExporter {
  static Future<void> exportMeeting(Meeting meeting) async {
    // Generate an ICS conforming to RFC 5545
    // Dates must be in UTC for ICS (format YYYYMMDDTHHmmssZ)
    final DateFormat formatter = DateFormat("yyyyMMdd'T'HHmmss'Z'");
    
    // We already keep meeting.start and meeting.end in UTC
    final dtstart = formatter.format(meeting.start);
    final dtend = formatter.format(meeting.end);
    final dtstamp = formatter.format(DateTime.now().toUtc());
    
    final uid = meeting.id.toString() + "@smartscheduler.local";
    final summary = meeting.title.replaceAll(',', '\\,').replaceAll('\n', '\\n');
    final description = (meeting.title).replaceAll(',', '\\,').replaceAll('\n', '\\n');
    
    final String icsContent = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//SmartScheduler//App//EN
CALSCALE:GREGORIAN
BEGIN:VEVENT
UID:$uid
DTSTAMP:$dtstamp
DTSTART:$dtstart
DTEND:$dtend
SUMMARY:$summary
DESCRIPTION:$description
END:VEVENT
END:VCALENDAR''';

    // Encode to Data URI
    final Uri uri = Uri.parse('data:text/calendar;charset=utf8,${Uri.encodeComponent(icsContent)}');
    
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        // Fallback for some platforms: try to launch an intermediate HTML or direct download
        print("Could not launch ICS data URI directly");
      }
    } catch (e) {
      print("Error launching ICS: $e");
    }
  }
}
