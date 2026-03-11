import 'package:json_annotation/json_annotation.dart';
import '../utils/timezone_utils.dart';

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

  factory TimeSlot.fromJson(Map<String, dynamic> json) => TimeSlot(
    start: toUserLocal(DateTime.parse(json['start'] as String)),
    end: toUserLocal(DateTime.parse(json['end'] as String)),
    type: json['type'] as String? ?? 'match',
    availability: (json['availability'] as num?)?.toDouble() ?? 1.0,
    freeCount: json['free_count'] as int?,
    totalCount: json['total_count'] as int?,
  );
  Map<String, dynamic> toJson() => _$TimeSlotToJson(this);
  
  bool get isFullMatch => type == 'match';
  bool get isMyBusy => type == 'my_busy';
  bool get isOthersBusy => type == 'others_busy';
}
