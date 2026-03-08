import 'package:json_annotation/json_annotation.dart';

part 'busy_slot.g.dart';

@JsonSerializable()
class BusySlot {
  final String? id;
  final DateTime startTime;
  final DateTime endTime;

  BusySlot({
    this.id,
    required this.startTime,
    required this.endTime,
  });

  factory BusySlot.fromJson(Map<String, dynamic> json) => _$BusySlotFromJson(json);
  Map<String, dynamic> toJson() => _$BusySlotToJson(this);
}
