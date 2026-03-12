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

    // FIX 1: gridStart must be a LOCAL date (not UTC) so that
    // DateUtils.dateOnly(localStart).difference(gridStart) is always correct.
    final today = DateTime(now.year, now.month, now.day); // LOCAL midnight

    final int dayOffset = selectedDay.difference(today).inDays;
    final DateTime gridStart = dayOffset >= 7
        ? today.add(const Duration(days: 7))
        : today;

    // 2. Group slots by hour and day-column index
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

      // FIX 1 cont: Both sides of difference() are now LOCAL datetimes
      final localStartDay = DateTime(localStart.year, localStart.month, localStart.day);
      final localEndDay   = DateTime(localEnd.year,   localEnd.month,   localEnd.day);

      final int startDiff = localStartDay.difference(gridStart).inDays;
      final int endDiff   = localEndDay.difference(gridStart).inDays;

      for (int currentDiff = startDiff; currentDiff <= endDiff; currentDiff++) {
        if (currentDiff < 0 || currentDiff >= 7) continue;

        int startHour = 7;
        int endHour   = 23;

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
        // ── Days Header ──────────────────────────────────────────────
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
                final isToday    = DateUtils.isSameDay(day, now);
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
                            color: isSelected
                                ? Colors.blue
                                : (isToday ? Colors.green : Colors.white70),
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

        // ── Time Grid ────────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: 17, // 7:00 – 23:00
            itemBuilder: (context, index) {
              final hour = index + 7;

              return SizedBox(
                height: 50,
                child: Row(
                  children: [
                    // Time label
                    SizedBox(
                      width: 50,
                      child: Text(
                        '$hour:00',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    // 7 day columns
                    ...List.generate(7, (dayIndex) {
                      final day = gridStart.add(Duration(days: dayIndex));
                      final cellSlots = gridData[hour]?[dayIndex] ?? [];
                      final isSelectedColumn = DateUtils.isSameDay(day, selectedDay);

                      // FIX 2: Past cell is anything that has started in the past
                      final cellStartLocal = DateTime(
                        day.year, day.month, day.day, hour,
                      );
                      
                      // An hour block is past if its start time is before the current hour on the same day,
                      // OR if the cell's date is strictly before today's date.
                      final isPast = cellStartLocal.isBefore(
                        DateTime(now.year, now.month, now.day, now.hour)
                      );

                      return Expanded(
                        child: GestureDetector(
                          // FIX 2: past cells are not tappable
                          onTap: (!isPast && cellSlots.isNotEmpty)
                              ? () {
                                  final baseSlot = cellSlots.first;
                                  // Build a granular UTC slot for the tapped cell
                                  final clickedStart = DateTime(
                                    day.year, day.month, day.day, hour,
                                  ).toUtc();
                                  final clickedEnd =
                                      clickedStart.add(const Duration(hours: 1));
                                  onSlotSelected(TimeSlot(
                                    start: clickedStart,
                                    end: clickedEnd,
                                    type: baseSlot.type,
                                    availability: baseSlot.availability,
                                  ));
                                }
                              : null,
                          child: Container(
                            margin: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              color: isSelectedColumn
                                  ? Colors.white.withOpacity(0.04)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelectedColumn
                                    ? Colors.blue.withOpacity(0.3)
                                    : Colors.transparent,
                                width: 0.5,
                              ),
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: Stack(
                              children: [
                                // FIX 2: Past overlay — always on top of everything
                                if (isPast)
                                  Positioned.fill(
                                    child: Container(
                                      color: Colors.black.withOpacity(0.55),
                                    ),
                                  ),

                                // ── Base slot colour layer ──
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
                                              width: double.infinity,
                                              decoration: BoxDecoration(
                                                color: _getSlotColor(slot),
                                                borderRadius: BorderRadius.circular(2),
                                                border: Border.all(
                                                  color: slot.availability == 1.0
                                                      ? Colors.white.withOpacity(0.2)
                                                      : Colors.transparent,
                                                  width: 0.5,
                                                ),
                                              ),
                                              child: slot.availability > 0 &&
                                                      frac.height >= 25
                                                  ? Center(
                                                      child: Text(
                                                        '${(slot.availability * 100).toInt()}%',
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

                                // ── Purple meeting overlay ──
                                ...myMeetings.where((m) {
                                  final cellStart =
                                      gridStart.add(Duration(days: dayIndex, hours: hour));
                                  final cellEnd =
                                      cellStart.add(const Duration(hours: 1));
                                  final mStart = toUserLocal(m.start);
                                  final mEnd   = toUserLocal(m.end);
                                  final latestStart =
                                      mStart.isAfter(cellStart) ? mStart : cellStart;
                                  final earliestEnd =
                                      mEnd.isBefore(cellEnd) ? mEnd : cellEnd;
                                  // Add a small buffer of 1 minute to prevent rounding edge cases on rendering
                                  return latestStart.isBefore(earliestEnd.add(const Duration(minutes: 1)));
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
                                        if (frac.bottom > 0) Spacer(flex: frac.bottom),
                                      ],
                                    ),
                                  );
                                }),
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
    if (slot.isFullMatch)   return const Color(0xFF2E7D32).withOpacity(0.8); // green
    if (slot.isMyBusy)      return Colors.blue.withOpacity(0.6);             // blue
    if (slot.isOthersBusy)  return Colors.deepOrange.withOpacity(0.5);       // orange
    return Colors.black.withOpacity(0.05);
  }
}

/// Simple immutable struct for top/height/bottom flex values.
class _Frac {
  final int top;
  final int height;
  final int bottom;
  const _Frac(this.top, this.height, this.bottom);
}
