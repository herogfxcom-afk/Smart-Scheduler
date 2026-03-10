class Meeting {
  final int id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? location;
  final int? groupId;
  final String? inviteStatus;
  final bool isCreator;

  Meeting({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.location,
    this.groupId,
    this.inviteStatus,
    this.isCreator = false,
  });

  factory Meeting.fromJson(Map<String, dynamic> json) {
    return Meeting(
      id: json['id'] as int,
      title: json['title'] as String,
      start: DateTime.parse(json['start'] as String).toLocal(),
      end: DateTime.parse(json['end'] as String).toLocal(),
      location: json['location'] as String?,
      groupId: json['group_id'] as int?,
      inviteStatus: json['invite_status'] as String?,
      isCreator: json['is_creator'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'start': start.toUtc().toIsoformat(),
      'end': end.toUtc().toIsoformat(),
      'location': location,
      'group_id': groupId,
    };
  }
}

extension DateTimeFormat on DateTime {
  String toIsoformat() => toIso8601String().replaceFirst('Z', '+00:00');
}
