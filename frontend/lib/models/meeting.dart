import '../utils/timezone_utils.dart';

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
  });

  factory Meeting.fromJson(Map<String, dynamic> json) {
    return Meeting(
      id: json['id'] as int,
      title: json['title'] as String,
      start: DateTime.parse(json['start'] as String),
      end: DateTime.parse(json['end'] as String),
      location: json['location'] as String?,
      groupId: json['group_id'] as int?,
      groupTitle: json['group_title'] as String?,
      status: json['status'] as String? ?? 'accepted',
      inviteId: json['invite_id'] as int?,
      isCreator: json['is_creator'] as bool? ?? false,
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
    };
  }
}

extension DateTimeFormat on DateTime {
  String toIsoformat() => toIso8601String().replaceFirst('Z', '+00:00');
}
