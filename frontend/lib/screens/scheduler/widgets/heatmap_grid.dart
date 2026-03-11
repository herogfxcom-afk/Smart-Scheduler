import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/time_slot.dart';
import '../../../models/meeting.dart';
import '../../../providers/scheduler_provider.dart';

class HeatmapGrid extends StatelessWidget {
  final List<TimeSlot> slots;
  final DateTime selectedDay;
  final Function(TimeSlot) onSlotSelected;
  final List<String> ignoredParticipantIds;
  final List<Meeting> myMeetings;

  const HeatmapGrid({
    super.key,
    required this.slots,
    required this.selectedDay,
    required this.onSlotSelected,
    this.ignoredParticipantIds = const [],
    this.myMeetings = const [],
  });

  @override
  Widget build(BuildContext context) {
    // 1. Calculate the start date for the grid. 
    // We want it to be "Today" normalized if the selected day is in the current timeframe,
    // to match the top bar's behavior.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // If selectedDay is more than 6 days ahead, we show a second week window
    final int dayOffset = selectedDay.difference(today).inDays;
    final DateTime gridStart = dayOffset >= 7 
        ? today.add(const Duration(days: 7)) 
        : today;

    // 2. Group slots by hour and offset date
    final Map<int, Map<int, TimeSlot?>> gridData = {};
    for (int hour = 7; hour < 24; hour++) {
      gridData[hour] = {};
    }

    for (final slot in slots) {
      final localStart = slot.start.toLocal();
      final localEnd = slot.end.toLocal();
      
      final int diff = localStart.difference(gridStart).inDays;
      if (diff >= 0 && diff < 7) {
        // Fill all hours this slot covers
        int startHour = localStart.hour;
        int endHour = localEnd.hour;
        
        // If it spans midnight, cap at 24 for today
        if (localEnd.day != localStart.day) endHour = 24;

        for (int h = startHour; h < endHour; h++) {
          if (h >= 7 && h < 24) {
            gridData[h]![diff] = slot;
          }
        }
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
                final day = gridStart.add(Duration(days: index));
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
            padding: const EdgeInsets.only(bottom: 80), // Added padding for better scrolling
            itemCount: 17, // 7:00 to 23:00 (up to 24:00)
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
                      final day = gridStart.add(Duration(days: dayIndex));
                      final isSelectedColumn = DateUtils.isSameDay(day, selectedDay);
                      
                      return Expanded(
                        child: GestureDetector(
                          onTap: slot != null ? () => onSlotSelected(slot) : null,
                          child: Container(
                            margin: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              color: slot != null ? _getSlotColor(slot) : (isSelectedColumn ? Colors.white.withOpacity(0.04) : Colors.transparent),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelectedColumn 
                                  ? Colors.blue.withOpacity(0.3) 
                                  : (slot != null && slot.availability == 1.0 ? Colors.white.withOpacity(0.2) : Colors.transparent),
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
    
    // 4-Color Logic
    if (slot.isFullMatch) {
      return const Color(0xFF2E7D32).withOpacity(0.8); // Green: Everyone is free
    } else if (slot.isMyBusy) {
      // Подсчет: если это слот моей встречи из приложения, красим в фиолетовый
      final sStart = slot.start.toLocal();
      final sEnd = slot.end.toLocal();
      bool isAppMeeting = false;
      
      for (final m in myMeetings) {
        final mStart = m.start.toLocal();
        final mEnd = m.end.toLocal();
        
        // Calculate max of starts and min of ends
        final latestStart = sStart.isAfter(mStart) ? sStart : mStart;
        final earliestEnd = sEnd.isBefore(mEnd) ? sEnd : mEnd;

        if (latestStart.isBefore(earliestEnd)) {
          isAppMeeting = true;
          break;
        }
      }
      
      if (isAppMeeting) {
        return Colors.purple.withOpacity(0.6); // Purple: App created meeting
      } else {
        return Colors.blue.withOpacity(0.6); // Blue: Personal Google event
      }
    } else if (slot.isOthersBusy) {
      return Colors.deepOrange.withOpacity(0.5); // Orange: Someone else is busy
    }
    
    // Fallback
    return Colors.black.withOpacity(0.05);
  }
}
