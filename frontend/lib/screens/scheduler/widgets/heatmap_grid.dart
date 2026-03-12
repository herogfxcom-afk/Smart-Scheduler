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
    final DateTime gridStart = dayOffset >= 7 ? today.add(const Duration(days: 7)) : today;

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

      final localStartDay = DateTime(localStart.year, localStart.month, localStart.day);
      final localEndDay = DateTime(localEnd.year, localEnd.month, localEnd.day);

      final int startDiff = localStartDay.difference(gridStart).inDays;
      final int endDiff = localEndDay.difference(gridStart).inDays;

      for (int currentDiff = startDiff; currentDiff <= endDiff; currentDiff++) {
        if (currentDiff < 0 || currentDiff >= 7) continue;

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

    return Column(
      children: [
        // Days Header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
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
                          DateFormat('E').format(day).toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 0.5,
                            fontWeight: FontWeight.w800,
                            color: isSelected ? Colors.blueAccent : Colors.white24,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: isSelected
                              ? const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle)
                              : (isToday ? BoxDecoration(border: Border.all(color: Colors.greenAccent.withOpacity(0.5)), shape: BoxShape.circle) : null),
                          child: Text(
                            day.day.toString(),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Colors.white : (isToday ? Colors.greenAccent : Colors.white70),
                            ),
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

        // Time Grid
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: 17, // 7:00 – 23:00
            itemBuilder: (context, index) {
              final hour = index + 7;

              return SizedBox(
                height: 56,
                child: Row(
                  children: [
                    // Time Label
                    SizedBox(
                      width: 50,
                      child: Center(
                        child: Text(
                          '${hour.toString().padLeft(2, '0')}:00',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white30,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    // 7 Columns
                    ...List.generate(7, (dayIndex) {
                      final day = gridStart.add(Duration(days: dayIndex));
                      final cellSlots = gridData[hour]?[dayIndex] ?? [];
                      final isSelectedColumn = DateUtils.isSameDay(day, selectedDay);

                      final cellStartLocal = DateTime(day.year, day.month, day.day, hour);
                      final cellEndLocal = cellStartLocal.add(const Duration(hours: 1));
                      
                      // Soft isPast: only block if the hour has strictly passed (minute-based)
                      final isPast = cellEndLocal.isBefore(now);

                      return Expanded(
                        child: GestureDetector(
                          onTap: (!isPast && cellSlots.isNotEmpty)
                              ? () {
                                  final baseSlot = cellSlots.first;
                                  final clickedStart = cellStartLocal.toUtc();
                                  final clickedEnd = clickedStart.add(const Duration(hours: 1));
                                  onSlotSelected(TimeSlot(
                                    start: clickedStart,
                                    end: clickedEnd,
                                    type: baseSlot.type,
                                    availability: baseSlot.availability,
                                  ));
                                }
                              : null,
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelectedColumn ? Colors.white.withOpacity(0.01) : Colors.transparent,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.03),
                                width: 0.5,
                              ),
                            ),
                            child: Stack(
                              children: [
                                // 1. Base slots (Availability)
                                if (!isPast)
                                  ...cellSlots.map((slot) {
                                    final cellStartDt = gridStart.add(Duration(days: dayIndex, hours: hour));
                                    final frac = _calcFraction(slot, cellStartDt);
                                    if (frac.height <= 0) return const SizedBox.shrink();

                                    return Positioned.fill(
                                      child: Column(
                                        children: [
                                          if (frac.top > 0) Spacer(flex: frac.top),
                                          Expanded(
                                            flex: frac.height,
                                            child: Container(
                                              margin: const EdgeInsets.symmetric(horizontal: 1),
                                              decoration: BoxDecoration(
                                                color: _getSlotColor(slot),
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                            ),
                                          ),
                                          if (frac.bottom > 0) Spacer(flex: frac.bottom),
                                        ],
                                      ),
                                    );
                                  }),

                                // 2. Meetings (Purple)
                                ...myMeetings.where((m) {
                                  final mStart = toUserLocal(m.start);
                                  final mEnd = toUserLocal(m.end);
                                  return (mStart.isBefore(cellEndLocal) && mEnd.isAfter(cellStartLocal));
                                }).map((meeting) {
                                  final cellStartDt = gridStart.add(Duration(days: dayIndex, hours: hour));
                                  final frac = _calcMeetingFraction(meeting, cellStartDt);
                                  if (frac.height <= 0) return const SizedBox.shrink();

                                  return Positioned.fill(
                                    child: Column(
                                      children: [
                                        if (frac.top > 0) Spacer(flex: frac.top),
                                        Expanded(
                                          flex: frac.height,
                                          child: Container(
                                            margin: const EdgeInsets.symmetric(horizontal: 0.5),
                                            decoration: BoxDecoration(
                                              color: Colors.purpleAccent.withOpacity(0.8),
                                              borderRadius: BorderRadius.circular(2),
                                              border: Border.all(color: Colors.white24, width: 0.5),
                                            ),
                                          ),
                                        ),
                                        if (frac.bottom > 0) Spacer(flex: frac.bottom),
                                      ],
                                    ),
                                  );
                                }),

                                // 3. Past Overlay (Softer)
                                if (isPast)
                                  Positioned.fill(
                                    child: Container(
                                      color: const Color(0xFF121212).withOpacity(0.5),
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
    
    if (!latestStart.isBefore(earliestEnd)) {
      return const _Frac(0, 0, 0);
    }
    
    final topMinutes = latestStart.difference(cellStart).inMinutes;
    final meetingMinutes = earliestEnd.difference(latestStart).inMinutes;
    
    if (meetingMinutes <= 0) return const _Frac(0, 0, 0);

    final top = ((topMinutes / 60.0) * 100).round().clamp(0, 100);
    final height = ((meetingMinutes / 60.0) * 100).round().clamp(1, 100 - top);
    final bottom = (100 - top - height).clamp(0, 100);
    
    return _Frac(top, height, bottom);
  }

  Color _getSlotColor(TimeSlot slot) {
    if (slot.isFullMatch)   return Colors.greenAccent.withOpacity(0.4); 
    if (slot.isMyBusy)      return Colors.blueAccent.withOpacity(0.3);             
    if (slot.isOthersBusy)  return Colors.orangeAccent.withOpacity(0.3);       
    return Colors.white.withOpacity(0.02);
  }
}

class _Frac {
  final int top;
  final int height;
  final int bottom;
  const _Frac(this.top, this.height, this.bottom);
}

