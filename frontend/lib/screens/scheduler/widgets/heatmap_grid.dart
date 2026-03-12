import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/time_slot.dart';
import '../../../models/meeting.dart';
import '../../../providers/scheduler_provider.dart';
import '../../../utils/timezone_utils.dart';

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
    final now = userNow();
    final today = DateTime(now.year, now.month, now.day);
    
    final int dayOffset = selectedDay.difference(today).inDays;
    final DateTime gridStart = dayOffset >= 7 
        ? today.add(const Duration(days: 7)) 
        : today;

    // 2. Group slots by hour and offset date
    final Map<int, Map<int, List<TimeSlot>>> gridData = {};
    for (int hour = 7; hour < 24; hour++) {
      gridData[hour] = {};
      for (int i = 0; i < 7; i++) {
        gridData[hour]![i] = [];
      }
    }

    for (final slot in slots) {
      final localStart = toUserLocal(slot.start);
      final localEnd = toUserLocal(slot.end);
      
      final int startDiff = DateUtils.dateOnly(localStart).difference(gridStart).inDays;
      final int endDiff = DateUtils.dateOnly(localEnd).difference(gridStart).inDays;

      for (int currentDiff = startDiff; currentDiff <= endDiff; currentDiff++) {
        if (currentDiff >= 0 && currentDiff < 7) {
          int startHour = 7;
          int endHour = 24;

          if (currentDiff == startDiff) {
            startHour = localStart.hour;
          }
          if (currentDiff == endDiff) {
            endHour = localEnd.hour;
            if (localEnd.minute == 0 && endHour > startHour) {
              endHour -= 1;
            }
          }

          for (int h = startHour; h <= endHour; h++) {
            if (h >= 7 && h < 24) {
              gridData[h]![currentDiff]!.add(slot);
            }
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
                final isToday = DateUtils.isSameDay(day, userNow());
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
            padding: const EdgeInsets.only(bottom: 80), 
            itemCount: 17, // 7:00 to 24:00
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
                      final cellSlots = gridData[hour]?[dayIndex] ?? [];
                      final day = gridStart.add(Duration(days: dayIndex));
                      final isSelectedColumn = DateUtils.isSameDay(day, selectedDay);
                      
                      return Expanded(
                        child: GestureDetector(
                          onTap: cellSlots.isNotEmpty ? () {
                            // Instead of picking the first merged slot (which could be the whole day),
                            // we create a granular 1-hour slot starting at the clicked hour.
                            final baseSlot = cellSlots.first;
                            final clickedStart = DateTime(day.year, day.month, day.day, hour, 0).toUtc();
                            final clickedEnd = clickedStart.add(const Duration(hours: 1));
                            
                            // Ensure the 1-hour slot is within the bounds of the merged block
                            // (though for 'match' type it usually is)
                            final granularSlot = TimeSlot(
                              start: clickedStart,
                              end: clickedEnd,
                              type: baseSlot.type,
                              availability: baseSlot.availability,
                            );
                            onSlotSelected(granularSlot);
                          } : null,
                          child: Container(
                            margin: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              color: isSelectedColumn ? Colors.white.withOpacity(0.04) : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelectedColumn ? Colors.blue.withOpacity(0.3) : Colors.transparent,
                                width: 0.5,
                              ),
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: Stack(
                              children: [
                                // Base slots layer
                                ...cellSlots.map((slot) {
                                  double topFactor = 0.0;
                                  double heightFactor = 1.0;

                                  final localStart = toUserLocal(slot.start);
                                  final localEnd = toUserLocal(slot.end);

                                  if (localStart.hour == hour) {
                                    topFactor = localStart.minute / 60.0;
                                    heightFactor -= topFactor;
                                  }

                                  if (localEnd.hour == hour && (localEnd.day == localStart.day || localEnd.hour != 0)) {
                                    double bottomFactor = (60 - localEnd.minute) / 60.0;
                                    if (localEnd.minute > 0) {
                                      heightFactor -= bottomFactor;
                                    } else {
                                      heightFactor = 0.0;
                                    }
                                  }

                                  if (heightFactor <= 0.0) return const SizedBox.shrink();

                                  int flexTop = (topFactor * 100).round();
                                  int flexHeight = (heightFactor * 100).round();
                                  int flexBottom = 100 - flexTop - flexHeight;

                                  return Positioned.fill(
                                    child: Column(
                                      children: [
                                        if (flexTop > 0) Spacer(flex: flexTop),
                                        if (flexHeight > 0)
                                          Expanded(
                                            flex: flexHeight,
                                            child: Container(
                                              width: double.infinity,
                                              decoration: BoxDecoration(
                                                color: _getSlotColor(slot, hour, day),
                                                borderRadius: BorderRadius.circular(2),
                                                border: Border.all(
                                                  color: slot.availability == 1.0 ? Colors.white.withOpacity(0.2) : Colors.transparent,
                                                  width: 0.5,
                                                ),
                                              ),
                                              child: slot.availability > 0 && flexHeight >= 25
                                                  ? Center(
                                                      child: Text(
                                                        "${(slot.availability * 100).toInt()}%",
                                                        style: const TextStyle(
                                                          fontSize: 8,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                          ),
                                        if (flexBottom > 0) Spacer(flex: flexBottom),
                                      ],
                                    ),
                                  );
                                }).toList(),

                                // App meetings overlay layer (Purple boxes)
                                ...myMeetings.where((m) {
                                  final cellStart = gridStart.add(Duration(days: dayIndex, hours: hour));
                                  final cellEnd = cellStart.add(const Duration(hours: 1));
                                  final localStart = toUserLocal(m.start);
                                  final localEnd = toUserLocal(m.end);
                                  final latestStart = localStart.isAfter(cellStart) ? localStart : cellStart;
                                  final earliestEnd = localEnd.isBefore(cellEnd) ? localEnd : cellEnd;
                                  return latestStart.isBefore(earliestEnd);
                                }).map((meeting) {
                                  double mTopFactor = 0.0;
                                  double mHeightFactor = 1.0;

                                  final localStart = toUserLocal(meeting.start);
                                  final localEnd = toUserLocal(meeting.end);

                                  if (localStart.hour == hour) {
                                    mTopFactor = localStart.minute / 60.0;
                                    mHeightFactor -= mTopFactor;
                                  }

                                  if (localEnd.hour == hour && (localEnd.day == localStart.day || localEnd.hour != 0)) {
                                    double mBottomFactor = (60 - localEnd.minute) / 60.0;
                                    if (localEnd.minute > 0) {
                                      mHeightFactor -= mBottomFactor;
                                    } else {
                                      mHeightFactor = 0.0;
                                    }
                                  }

                                  if (mHeightFactor <= 0.0) return const SizedBox.shrink();

                                  int mFlexTop = (mTopFactor * 100).round();
                                  int mFlexHeight = (mHeightFactor * 100).round();
                                  int mFlexBottom = 100 - mFlexTop - mFlexHeight;

                                  return Positioned.fill(
                                    child: Column(
                                      children: [
                                        if (mFlexTop > 0) Spacer(flex: mFlexTop),
                                        if (mFlexHeight > 0)
                                          Expanded(
                                            flex: mFlexHeight,
                                            child: Container(
                                              width: double.infinity,
                                              decoration: BoxDecoration(
                                                color: Colors.purple.withOpacity(0.85),
                                                borderRadius: BorderRadius.circular(2),
                                                border: Border.all(
                                                  color: Colors.white.withOpacity(0.3),
                                                  width: 1.0,
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (mFlexBottom > 0) Spacer(flex: mFlexBottom),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ],
                            ),
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

  Color _getSlotColor(TimeSlot? slot, int cellHour, DateTime cellDay) {
    if (slot == null) return Colors.white.withOpacity(0.02);
    
    if (slot.isFullMatch) {
      return const Color(0xFF2E7D32).withOpacity(0.8); // Green
    } else if (slot.isMyBusy) {
      return Colors.blue.withOpacity(0.6); // Blue (Base busy)
    } else if (slot.isOthersBusy) {
      return Colors.deepOrange.withOpacity(0.5); // Orange
    }
    
    return Colors.black.withOpacity(0.05);
  }
}
