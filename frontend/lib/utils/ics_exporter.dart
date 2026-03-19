import 'package:url_launcher/url_launcher.dart';
import '../models/meeting.dart';

class IcsExporter {
  static Future<void> exportMeeting(Meeting meeting, String? token) async {
    if (token == null || token.isEmpty) {
      print("Cannot export ICS: No auth token provided");
      return;
    }

    const apiUrl = String.fromEnvironment('API_URL', defaultValue: '');
    final url = "${apiUrl}/api/meetings/${meeting.id}/ics?token=${Uri.encodeComponent(token)}";
    final uri = Uri.parse(url);
    
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        print("Could not launch ICS URL: $url");
      }
    } catch (e) {
      print("Error launching ICS: $e");
    }
  }
}
