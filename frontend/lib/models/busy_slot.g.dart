// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'busy_slot.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BusySlot _$BusySlotFromJson(Map<String, dynamic> json) => BusySlot(
      id: json['id'] as String?,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
    );

Map<String, dynamic> _$BusySlotToJson(BusySlot instance) => <String, dynamic>{
      'id': instance.id,
      'startTime': instance.startTime.toIso8601String(),
      'endTime': instance.endTime.toIso8601String(),
    };
