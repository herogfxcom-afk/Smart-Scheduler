class Availability {
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final bool isEnabled;

  Availability({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.isEnabled,
  });

  factory Availability.fromJson(Map<String, dynamic> json) {
    return Availability(
      dayOfWeek: json['day_of_week'] as int,
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      isEnabled: json['is_enabled'] == 1 || json['is_enabled'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'day_of_week': dayOfWeek,
      'start_time': startTime,
      'end_time': endTime,
      'is_enabled': isEnabled ? 1 : 0,
    };
  }

  String get dayName {
    switch (dayOfWeek) {
      case 0: return 'Понедельник';
      case 1: return 'Вторник';
      case 2: return 'Среда';
      case 3: return 'Четверг';
      case 4: return 'Пятница';
      case 5: return 'Суббота';
      case 6: return 'Воскресенье';
      default: return '';
    }
  }
}
