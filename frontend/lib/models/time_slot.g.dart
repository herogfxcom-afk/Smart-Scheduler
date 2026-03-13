// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'time_slot.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TimeSlot _$TimeSlotFromJson(Map<String, dynamic> json) => TimeSlot(
      start: DateTime.parse(json['start'] as String),
      end: DateTime.parse(json['end'] as String),
      type: json['type'] as String,
      availability: (json['availability'] as num?)?.toDouble() ?? 0.0,
      freeCount: (json['free_count'] as num?)?.toInt(),
      totalCount: (json['total_count'] as num?)?.toInt(),
      sourceUserId: json['source_user_id'] as String?,
    );

Map<String, dynamic> _$TimeSlotToJson(TimeSlot instance) => <String, dynamic>{
      'start': instance.start.toIso8601String(),
      'end': instance.end.toIso8601String(),
      'type': instance.type,
      'availability': instance.availability,
      'free_count': instance.freeCount,
      'total_count': instance.totalCount,
      'source_user_id': instance.sourceUserId,
    };
