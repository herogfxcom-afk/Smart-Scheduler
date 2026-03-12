import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/time_slot.dart';
import '../../../models/meeting.dart';
import '../../../utils/timezone_utils.dart';
import '../../../utils/calendar_processor.dart';

class HeatmapGrid extends StatelessWidget {
  final List<TimeSlot> slots;
  final DateTime selectedDay;
  final Function(TimeSlot) onSlotSelected;
  final List<Meeting> myMeetings;
  final CalendarType calendarType;

  const HeatmapGrid({
    super.key,
    required this.slots,
    required this.selectedDay,
    required this.onSlotSelected,
    this.myMeetings = const [],
    this.calendarType = CalendarType.group,
  });

  @override
  Widget build(BuildContext context) {
    final now = userNow();
    final String? myUserId = TelegramService().getUserId();
    final processor = CalendarProcessor(
      slots: slots,
      selectedDay: selectedDay,
      meetings: myMeetings,
      type: calendarType,
      myUserId: myUserId,
    );

    return Column(
      children: [
        // ... (Days Header logic stays same)
        // ...
        // ...
        // In the cell render loop:
        // ...
                          child: Container(
                            margin: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
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
                                ...cellSlots.map((ps) {
                                  final slot = ps.originalSlot;
                                  final frac = _calcFraction(slot, cellStartLocal);
                                  if (frac.height <= 0) return const SizedBox.shrink();

                                  return Positioned.fill(
                                    child: Column(
                                      children: [
                                        if (frac.top > 0) Spacer(flex: frac.top),
                                        Expanded(
                                          flex: frac.height,
                                          child: Tooltip(
                                            message: processor.getSlotTooltip(ps, myUserId),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: processor.getSlotColor(ps, myUserId),
                                                borderRadius: BorderRadius.circular(2),
                                                border: ps.isMeeting 
                                                  ? Border.all(color: Colors.white.withOpacity(0.4), width: 1.0)
                                                  : (slot.isFromMe(myUserId) ? Border.all(color: Colors.blue.withOpacity(0.8), width: 1.0) : null),
                                              ),
                                              child: !ps.isMeeting && slot.availability > 0 && frac.height >= 25
                                                  ? Center(
                                                      child: Text(
                                                        "${(slot.availability * 100).toInt()}%",
                                                        style: const TextStyle(
                                                          fontSize: 8,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.white24,
                                                        ),
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                          ),
                                        ),
                                        if (frac.bottom > 0) Spacer(flex: frac.bottom),
                                      ],
                                    ),
                                  );
                                }),

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
        _buildLegend(),
      ],
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: calendarType == CalendarType.group 
        ? [
            _legendItem(const Color(0xFF2E7D32), "Match"),
            _legendItem(Colors.blue, "Me"),
            _legendItem(Colors.deepOrange, "Others"),
            _legendItem(Colors.purple, "Meeting"),
          ]
        : [
            _legendItem(Colors.green, "Free"),
            _legendItem(Colors.orange, "Partial"),
            _legendItem(Colors.red, "Busy"),
          ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color.withOpacity(0.7), borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54)),
        ],
      ),
    );
  }

  _Frac _calcFraction(TimeSlot slot, DateTime cellStart) {
    final cellEnd = cellStart.add(const Duration(hours: 1));
    final localStart = toUserLocal(slot.start);
    final localEnd = toUserLocal(slot.end);
    
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
}

class _Frac {
  final int top;
  final int height;
  final int bottom;
  const _Frac(this.top, this.height, this.bottom);
}
