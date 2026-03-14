// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'calendar_connection.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CalendarConnection _$CalendarConnectionFromJson(Map<String, dynamic> json) =>
    CalendarConnection(
      id: (json['id'] as num?)?.toInt(),
      provider: json['provider'] as String,
      email: json['email'] as String?,
      status: json['status'] as String,
      isActive: json['is_active'] as bool? ?? true,
      lastSyncAt: json['last_sync_at'] == null
          ? null
          : DateTime.parse(json['last_sync_at'] as String),
      lastSyncStatus: json['last_sync_status'] as String?,
    );

Map<String, dynamic> _$CalendarConnectionToJson(CalendarConnection instance) =>
    <String, dynamic>{
      'id': instance.id,
      'provider': instance.provider,
      'email': instance.email,
      'status': instance.status,
      'is_active': instance.isActive,
      'last_sync_at': instance.lastSyncAt?.toIso8601String(),
      'last_sync_status': instance.lastSyncStatus,
    };
