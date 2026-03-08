import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/time_slot.dart';
import '../../../providers/scheduler_provider.dart';

class HeatmapGrid extends StatelessWidget {
  final List<TimeSlot> slots;
  final DateTime selectedDay;
  final Function(TimeSlot) onSlotSelected;
  final List<String> ignoredParticipantIds;

  const HeatmapGrid({
    super.key,
    required this.slots,
    required this.selectedDay,
    required this.onSlotSelected,
    this.ignoredParticipantIds = const [],
  });

  @override
  Widget build(BuildContext context) {
    // 1. Calculate the start of the current week (Monday) relative to selectedDay
    final int daysToMinus = selectedDay.weekday - 1;
    final DateTime weekStart = selectedDay.subtract(Duration(days: daysToMinus));

    // 2. Group slots by hour and offset date
    final Map<int, Map<int, TimeSlot?>> gridData = {};
    for (int hour = 7; hour < 23; hour++) {
      gridData[hour] = {};
    }

    for (final slot in slots) {
      final hour = slot.start.hour;
      // Find which day of the visible week this belongs to
      final diff = slot.start.difference(weekStart).inDays;
      if (hour >= 7 && hour < 23 && diff >= 0 && diff < 7) {
        gridData[hour]![diff] = slot;
      }
    }

    return Column(
      children: [
        // Days Header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const SizedBox(width: 50),
              ...List.generate(7, (index) {
                final day = weekStart.add(Duration(days: index));
                final isToday = DateUtils.isSameDay(day, DateTime.now());
                final isSelected = DateUtils.isSameDay(day, selectedDay);
                
                return Expanded(
                  child: Center(
                    child: Column(
                      children: [
                        Text(
                          DateFormat('E').format(day),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.blue : Colors.grey,
                          ),
                        ),
                        Text(
                          day.day.toString(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.blue : (isToday ? Colors.green : Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: 16, // 7:00 to 23:00
            itemBuilder: (context, index) {
              final hour = index + 7;
              return SizedBox(
                height: 50,
                child: Row(
                  children: [
                    // Time Label
                    SizedBox(
                      width: 50,
                      child: Text(
                        "$hour:00",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    // Days Grid
                    ...List.generate(7, (dayIndex) {
                      final slot = gridData[hour]?[dayIndex];
                      
                      return Expanded(
                        child: GestureDetector(
                          onTap: slot != null ? () => onSlotSelected(slot) : null,
                          child: Container(
                            margin: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              color: _getSlotColor(slot),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: slot != null && slot.availability == 1.0 
                                  ? Colors.white.withOpacity(0.2) 
                                  : Colors.transparent,
                                width: 0.5,
                              ),
                            ),
                            child: slot != null && slot.availability > 0
                              ? Center(
                                  child: Text(
                                    "${(slot.availability * 100).toInt()}%",
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: slot.availability > 0.5 ? Colors.white : Colors.white70,
                                    ),
                                  ),
                                )
                              : null,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getSlotColor(TimeSlot? slot) {
    if (slot == null) return Colors.white.withOpacity(0.02);
    
    final val = slot.availability;
    if (val == 1.0) return const Color(0xFF2E7D32).withOpacity(0.8);
    if (val >= 0.8) return const Color(0xFF43A047).withOpacity(0.6);
    if (val >= 0.6) return const Color(0xFFFBC02D).withOpacity(0.5);
    if (val >= 0.4) return const Color(0xFFF57C00).withOpacity(0.4);
    if (val > 0) return const Color(0xFFD32F2F).withOpacity(0.3);
    return Colors.black.withOpacity(0.05);
  }
}
