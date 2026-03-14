import '../utils/timezone_utils.dart';

/// Sanitizes ISO date strings that may have both an offset and trailing Z.
/// e.g. "2026-03-12T12:10:00+00:00Z" -> "2026-03-12T12:10:00+00:00"
DateTime _parseDate(String raw) {
  // If the string ends with Z but also has a +/- offset before Z, strip the Z
  if (raw.endsWith('Z') && raw.length > 1) {
    final withoutZ = raw.substring(0, raw.length - 1);
    // Check if there's already a timezone offset (+HH:MM or -HH:MM)
    final plusIdx = withoutZ.lastIndexOf('+');
    final minusIdx = withoutZ.lastIndexOf('-');
    final offsetIdx = plusIdx > minusIdx ? plusIdx : minusIdx;
    // Offset must be after 'T' and contain ':' (like +00:00)
    if (offsetIdx > withoutZ.indexOf('T') && withoutZ.substring(offsetIdx).contains(':')) {
      return DateTime.parse(withoutZ);
    }
  }
  return DateTime.parse(raw);
}

class Meeting {
  final int id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? location;
  final int? groupId;
  final String? groupTitle;
  final String status; // 'pending', 'accepted', 'declined'
  final int? inviteId;
  final bool isCreator;
  final bool isCancelled;

  Meeting({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.location,
    this.groupId,
    this.groupTitle,
    required this.status,
    this.inviteId,
    required this.isCreator,
    this.isCancelled = false,
  });

  factory Meeting.fromJson(Map<String, dynamic> json) {
    return Meeting(
      id: json['id'] as int,
      title: json['title'] as String,
      start: _parseDate(json['start'] as String),
      end: _parseDate(json['end'] as String),
      location: json['location'] as String?,
      groupId: json['group_id'] as int?,
      groupTitle: json['group_title'] as String?,
      status: json['status'] as String? ?? 'accepted',
      inviteId: json['invite_id'] as int?,
      isCreator: json['is_creator'] as bool? ?? false,
      isCancelled: json['is_cancelled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
      'location': location,
      'group_id': groupId,
      'group_title': groupTitle,
      'status': status,
      'invite_id': inviteId,
      'is_creator': isCreator,
      'is_cancelled': isCancelled,
    };
  }
}

extension DateTimeFormat on DateTime {
  String toIsoformat() => toIso8601String().replaceFirst('Z', '+00:00');
}
