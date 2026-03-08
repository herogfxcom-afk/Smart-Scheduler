import 'package:json_annotation/json_annotation.dart';

part 'time_slot.g.dart';

@JsonSerializable()
class TimeSlot {
  final DateTime start;
  final DateTime end;
  final String type; // 'match', 'high', 'partial', 'low'
  final double availability;
  @JsonKey(name: 'free_count')
  final int? freeCount;
  @JsonKey(name: 'total_count')
  final int? totalCount;

  TimeSlot({
    required this.start,
    required this.end,
    this.type = 'match',
    this.availability = 1.0,
    this.freeCount,
    this.totalCount,
  });

  factory TimeSlot.fromJson(Map<String, dynamic> json) => _$TimeSlotFromJson(json);
  Map<String, dynamic> toJson() => _$TimeSlotToJson(this);
  
  bool get isFullMatch => type == 'match' || availability == 1.0;
}
