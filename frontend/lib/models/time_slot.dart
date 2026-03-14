import 'package:json_annotation/json_annotation.dart';
import '../utils/timezone_utils.dart';

part 'time_slot.g.dart';

@JsonSerializable()
class TimeSlot {
  final DateTime start;
  final DateTime end;
  final String type; // 'match', 'high', 'partial', 'low', 'my_busy', 'others_busy'
  final double availability;
  @JsonKey(name: 'free_count')
  final int? freeCount;
  @JsonKey(name: 'total_count')
  final int? totalCount;
  
  @JsonKey(name: 'source_user_id')
  final String? sourceUserId;
  final String? summary;
  @JsonKey(name: 'is_external')
  final bool isExternal;

  const TimeSlot({
    required this.start,
    required this.end,
    required this.type,
    this.availability = 0.0,
    this.freeCount,
    this.totalCount,
    this.sourceUserId,
    this.summary,
    this.isExternal = false,
  });

  factory TimeSlot.fromJson(Map<String, dynamic> json) {
    return TimeSlot(
      start: DateTime.parse(json['start'] as String),
      end: DateTime.parse(json['end'] as String),
      type: json['type'] as String? ?? 'match',
      availability: (json['availability'] as num?)?.toDouble() ?? 0.0,
      freeCount: json['free_count'] as int?,
      totalCount: json['total_count'] as int?,
      sourceUserId: json['source_user_id']?.toString(),
      summary: json['summary'] as String?,
      isExternal: json['is_external'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'type': type,
        'availability': availability,
        'free_count': freeCount,
        'total_count': totalCount,
        'source_user_id': sourceUserId,
      };

  bool get isCommonSlot => type == 'match';
  bool get isFullMatch => type == 'match';
  bool get isMyBusy => type == 'my_busy' || type == 'busy';
  bool get isOthersBusy => type == 'others_busy';

  bool get isFromSolo => sourceUserId == null;
  bool get isFromGroup => sourceUserId != null;

  bool isFromMe(String? myUserId) {
    if (myUserId == null || sourceUserId == null) return false;
    return sourceUserId == myUserId || type == 'my_busy';
  }

  bool isFromOthers(String? myUserId) {
    if (type == 'match') return false;
    if (sourceUserId == null) return type == 'others_busy'; 
    if (myUserId == null) return true;
    return sourceUserId != myUserId;
  }

  int get priority {
    if (type == 'match') return 3;
    if (type == 'my_busy' || type == 'busy') return 1;
    return 2;
  }
}

