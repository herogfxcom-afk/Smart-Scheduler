import 'package:json_annotation/json_annotation.dart';

part 'calendar_connection.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class CalendarConnection {
  final int? id;
  final String provider;
  final String? email;
  final String status;
  final bool isActive;
  final DateTime? lastSyncAt;
  final String? lastSyncStatus;

  CalendarConnection({
    this.id,
    required this.provider,
    this.email,
    required this.status,
    this.isActive = true,
    this.lastSyncAt,
    this.lastSyncStatus,
  });

  factory CalendarConnection.fromJson(Map<String, dynamic> json) => _$CalendarConnectionFromJson(json);
  Map<String, dynamic> toJson() => _$CalendarConnectionToJson(this);
}
