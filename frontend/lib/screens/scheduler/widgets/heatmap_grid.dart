import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/time_slot.dart';
import '../../../models/meeting.dart';
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
    final now = userNow();
    final today = DateTime(now.year, now.month, now.day);
    
    final int dayOffset = selectedDay.difference(today).inDays;
    final DateTime gridStart = dayOffset >= 7 
        ? today.add(const Duration(days: 7)) 
        : today;

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
          int endHour = 23;

          if (currentDiff == startDiff) startHour = localStart.hour.clamp(7, 23);
          if (currentDiff == endDiff) {
            endHour = localEnd.hour;
            if (localEnd.minute == 0 && endHour > startHour) endHour -= 1;
            endHour = endHour.clamp(7, 23);
          }

          for (int h = startHour; h <= endHour; h++) {
            gridData[h]![currentDiff]!.add(slot);
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
                final isToday = DateUtils.isSameDay(day, now);
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
                    ...List.generate(7, (dayIndex) {
                      final day = gridStart.add(Duration(days: dayIndex));
                      final cellSlots = gridData[hour]?[dayIndex] ?? [];
                      final isSelectedColumn = DateUtils.isSameDay(day, selectedDay);

                      final cellStartLocal = DateTime(day.year, day.month, day.day, hour);
                      final cellEndLocal = cellStartLocal.add(const Duration(hours: 1));
                      final isPast = cellEndLocal.isBefore(now);
                      
                      return Expanded(
                        child: GestureDetector(
                          onTap: (!isPast && cellSlots.isNotEmpty) ? () {
                            final baseSlot = cellSlots.first;
                            final clickedStart = cellStartLocal.toUtc();
                            final clickedEnd = clickedStart.add(const Duration(hours: 1));
                            
                            onSlotSelected(TimeSlot(
                              start: clickedStart,
                              end: clickedEnd,
                              type: baseSlot.type,
                              availability: baseSlot.availability,
                            ));
                          } : null,
                          child: Container(
                            margin: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              // Base color so grid structure is always visible
                              color: isSelectedColumn 
                                  ? Colors.white.withOpacity(0.06) 
                                  : Colors.white.withOpacity(0.01),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelectedColumn 
                                    ? Colors.blue.withOpacity(0.3) 
                                    : Colors.white.withOpacity(0.03),
                                width: 0.5,
                              ),
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: Stack(
                              children: [
                                // Base slots layer
                                ...cellSlots.map((slot) {
                                  final frac = _calcFraction(slot, cellStartLocal);
                                  if (frac.height <= 0) return const SizedBox.shrink();

                                  return Positioned.fill(
                                    child: Column(
                                      children: [
                                        if (frac.top > 0) Spacer(flex: frac.top),
                                        Expanded(
                                          flex: frac.height,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: _getSlotColor(slot),
                                              borderRadius: BorderRadius.circular(2),
                                              border: Border.all(
                                                color: slot.availability == 1.0 ? Colors.white.withOpacity(0.2) : Colors.transparent,
                                                width: 0.5,
                                              ),
                                            ),
                                            child: slot.availability > 0 && frac.height >= 25
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
                                        if (frac.bottom > 0) Spacer(flex: frac.bottom),
                                      ],
                                    ),
                                  );
                                }),

                                // Meetings (Purple)
                                ...myMeetings.where((m) {
                                  final mStart = toUserLocal(m.start);
                                  final mEnd = toUserLocal(m.end);
                                  return mStart.isBefore(cellEndLocal) && mEnd.isAfter(cellStartLocal);
                                }).map((meeting) {
                                  final frac = _calcMeetingFraction(meeting, cellStartLocal);
                                  if (frac.height <= 0) return const SizedBox.shrink();

                                  return Positioned.fill(
                                    child: Column(
                                      children: [
                                        if (frac.top > 0) Spacer(flex: frac.top),
                                        Expanded(
                                          flex: frac.height,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.purple.withOpacity(0.85),
                                              borderRadius: BorderRadius.circular(2),
                                              border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.0),
                                            ),
                                          ),
                                        ),
                                        if (frac.bottom > 0) Spacer(flex: frac.bottom),
                                      ],
                                    ),
                                  );
                                }),

                                // Past overlay (Soft dimming)
                                if (isPast)
                                  Positioned.fill(
                                    child: Container(
                                      color: Colors.black.withOpacity(0.4),
                                    ),
                                  ),
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

  // ── Helpers ──────────────────────────────────────────────────────

  _Frac _calcFraction(TimeSlot slot, DateTime cellStart) {
    return _fractionForRange(toUserLocal(slot.start), toUserLocal(slot.end), cellStart);
  }

  _Frac _calcMeetingFraction(Meeting meeting, DateTime cellStart) {
    return _fractionForRange(toUserLocal(meeting.start), toUserLocal(meeting.end), cellStart);
  }

  _Frac _fractionForRange(DateTime localStart, DateTime localEnd, DateTime cellStart) {
    final cellEnd = cellStart.add(const Duration(hours: 1));
    final latestStart = localStart.isAfter(cellStart) ? localStart : cellStart;
    final earliestEnd = localEnd.isBefore(cellEnd) ? localEnd : cellEnd;
    
    if (!latestStart.isBefore(earliestEnd)) return const _Frac(0, 0, 0);
    
    final topMinutes = latestStart.difference(cellStart).inMinutes;
    final durationMinutes = earliestEnd.difference(latestStart).inMinutes;
    
    if (durationMinutes <= 0) return const _Frac(0, 0, 0);

    final top = ((topMinutes / 60.0) * 100).round();
    final height = ((durationMinutes / 60.0) * 100).round();
    final bottom = 100 - top - height;
    
    return _Frac(top, height, bottom);
  }

  Color _getSlotColor(TimeSlot slot) {
    if (slot.isFullMatch)   return const Color(0xFF2E7D32).withOpacity(0.8);
    if (slot.isMyBusy)      return Colors.blue.withOpacity(0.6);
    if (slot.isOthersBusy)  return Colors.deepOrange.withOpacity(0.5);
    return Colors.black.withOpacity(0.05);
  }
}

class _Frac {
  final int top;
  final int height;
  final int bottom;
  const _Frac(this.top, this.height, this.bottom);
}


