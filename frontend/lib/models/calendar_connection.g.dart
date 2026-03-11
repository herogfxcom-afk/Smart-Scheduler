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
      lastSync: json['last_sync'] == null
          ? null
          : DateTime.parse(json['last_sync'] as String),
    );

Map<String, dynamic> _$CalendarConnectionToJson(CalendarConnection instance) =>
    <String, dynamic>{
      'id': instance.id,
      'provider': instance.provider,
      'email': instance.email,
      'status': instance.status,
      'is_active': instance.isActive,
      'last_sync': instance.lastSync?.toIso8601String(),
    };
