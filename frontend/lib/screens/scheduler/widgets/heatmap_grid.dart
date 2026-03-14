import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import '../../../models/time_slot.dart';
import '../../../models/meeting.dart';
import '../../../utils/timezone_utils.dart';
import '../../../utils/calendar_processor.dart';
import '../../../providers/working_hours_notifier.dart';
import '../../../models/availability.dart';
import 'package:provider/provider.dart';

class HeatmapGrid extends StatefulWidget {
  final List<TimeSlot> slots;
  final DateTime selectedDay;
  final Function(TimeSlot) onSlotSelected;
  final List<Meeting> myMeetings;
  final List<Availability> availability;
  final String? myUserId;
  final CalendarType calendarType;

  const HeatmapGrid({
    super.key,
    required this.slots,
    required this.selectedDay,
    required this.onSlotSelected,
    required this.availability,
    this.myUserId,
    this.myMeetings = const [],
    this.calendarType = CalendarType.group,
  });

  @override
  State<HeatmapGrid> createState() => _HeatmapGridState();
}

class _HeatmapGridState extends State<HeatmapGrid> {
  final CalendarController _calendarController = CalendarController();

  @override
  void initState() {
    super.initState();
    // Update notifier in initState (NOT in build!) to avoid state mutation during render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<WorkingHoursNotifier>().update(widget.availability);
      }
    });
  }

  @override
  void didUpdateWidget(covariant HeatmapGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!DateUtils.isSameDay(oldWidget.selectedDay, widget.selectedDay)) {
      _calendarController.displayDate = widget.selectedDay;
    }
    // Update notifier safely after the frame, never during build
    if (oldWidget.availability != widget.availability) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<WorkingHoursNotifier>().update(widget.availability);
        }
      });
    }
    _refreshCalendar();
  }

  void _refreshCalendar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _calendarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      final workingHoursNotifier = context.watch<WorkingHoursNotifier>();
      final regions = workingHoursNotifier.buildRegions().toList(); // copy to editable list

      // De-duplication set to prevent overlapping background regions
      final Set<String> addedRegions = {};

      // Helper to add region safely
      void addSafeRegion(DateTime start, DateTime end, Color color) {
        final key = "${start.toIso8601String()}_${end.toIso8601String()}_${color.value}";
        if (addedRegions.contains(key)) return;
        addedRegions.add(key);
        regions.add(TimeRegion(
          startTime: start,
          endTime: end,
          color: color,
          enablePointerInteraction: true,
        ));
      }

      // Add External Busy Slots (Outlook/Google) as background regions
      for (final slot in widget.slots) {
        if (!slot.isMyBusy) continue;

        final startUtc = slot.start.isUtc ? slot.start : slot.start.toUtc();
        final endUtc = slot.end.isUtc ? slot.end : slot.end.toUtc();
        addSafeRegion(startUtc, endUtc, Colors.blue.withOpacity(0.4));
      }

      // Add Other Participants' Busy Slots as background regions (Only in Group mode)
      if (widget.calendarType == CalendarType.group) {
        for (final slot in widget.slots) {
          if (!slot.isOthersBusy) continue;

          final startUtc = slot.start.isUtc ? slot.start : slot.start.toUtc();
          final endUtc = slot.end.isUtc ? slot.end : slot.end.toUtc();
          addSafeRegion(startUtc, endUtc, Colors.orange.withOpacity(0.3));
        }
      }

      return Column(
        children: [
        Expanded(
          child: SfCalendar(
            key: ValueKey('calendar_v\${workingHoursNotifier.version}'),
            controller: _calendarController,
            view: CalendarView.week,
            timeZone: getUserTimezone(),
            initialDisplayDate: widget.selectedDay,
            firstDayOfWeek: 1, // Monday
            timeSlotViewSettings: const TimeSlotViewSettings(
              startHour: 7,
              endHour: 24,
              timeInterval: Duration(hours: 1),
              timeFormat: 'H:mm',
              dateFormat: 'd',
              dayFormat: 'E',
              nonWorkingDays: [7], // Sunday
              timeIntervalHeight: 60,
            ),
            backgroundColor: Colors.transparent,
            headerHeight: 0,
            dataSource: _MeetingDataSource(_buildAppointments()),
            appointmentBuilder: _appointmentBuilder,
            specialRegions: regions,
            timeRegionBuilder: (context, details) {
              final color = details.region.color ?? Colors.green;
              // Add a border to almost all regions to keep them contained within grid cells
              final bool needsBorder = color.value != Colors.transparent.value;
              
              return Container(
                decoration: BoxDecoration(
                  color: color,
                  border: needsBorder 
                    ? Border.all(color: Colors.white.withOpacity(0.05), width: 0.5)
                    : null,
                ),
              );
            },
            onTap: (CalendarTapDetails details) {
              if (details.targetElement == CalendarElement.calendarCell) {
                final date = details.date;
                if (date != null) {
                  // Only allow selection if the slot is in the future
                  if (date.isBefore(userNow())) return;

                  // Validate working hours using local time
                  if (!_isWithinWorkingHours(date)) {
                    _showNonWorkingHourWarning(context);
                    return;
                  }
                  
                  // Construct a dummy TimeSlot for the selected cell
                  final selectedSlot = TimeSlot(
                    start: fromUserLocal(date),
                    end: fromUserLocal(date.add(const Duration(hours: 1))),
                    type: 'match',
                    availability: 1.0,
                  );
                  widget.onSlotSelected(selectedSlot);
                }
              } else if (details.targetElement == CalendarElement.appointment) {
                final ProcessedAppointment appt = details.appointments!.first;
                if (appt.startTime.isBefore(userNow())) return;
                widget.onSlotSelected(appt.originalSlot);
              }
            },
          ),
        ),
        _buildLegend(),
      ],
    );
    } catch (e, stack) {
      debugPrint("SfCalendar Build Error: $e\n$stack");
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.orange, size: 48),
              const SizedBox(height: 16),
              const Text("Ошибка отображения", 
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(e.toString(), 
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
        ),
      );
    }
  }



  List<ProcessedAppointment> _buildAppointments() {
    final List<ProcessedAppointment> appointments = [];
    final now = userNow();

    // 1. Add Meetings (Always visible in both solo and group)
    // IMPORTANT: Only add app-created meetings (purple). 
    // External synced events should NOT be added as foreground appointments 
    // because they are already added as background TimeRegions. 
    // Adding both causes "creeping" (split narrow columns).
    for (final meeting in widget.myMeetings) {
      // If the meeting is from an external provider, it will be in widget.slots as isMyBusy.
      // We skip it here to let the background TimeRegion handle it visually.
      if (meeting.provider != null && meeting.provider != 'app') continue;

      final startUtc = meeting.start.isUtc ? meeting.start : meeting.start.toUtc();
      final endUtc = meeting.end.isUtc ? meeting.end : meeting.end.toUtc();
      
      appointments.add(ProcessedAppointment(
        startTime: startUtc,
        endTime: endUtc,
        color: Colors.purple.withOpacity(0.85),
        subject: meeting.title,
        originalSlot: TimeSlot(start: meeting.start, end: meeting.end, type: 'meeting'),
        isMeeting: true,
        customMeeting: meeting,
      ));
    }

    // 2. External Busy Slots (Outlook/Google) are now handled via specialRegions (TimeRegions)
    // in the build() method to avoid "creeping" (split narrow columns).
    // We only keep app-created meetings in the foreground appointments list.

    // NOTE: We no longer add green "availability" or "common" slots as appointments.
    // The clickable area is handled by cell taps against the background working hours (specialRegions).
    // This ensures a clean UI without overlapping grid layers.

    return appointments;
  }



  Widget _appointmentBuilder(BuildContext context, CalendarAppointmentDetails details) {
    final ProcessedAppointment appt = details.appointments.first;
    final isPast = appt.isPast;
    final color = isPast ? Colors.grey.withOpacity(0.4) : appt.color;
    final hasBorder = appt.isMeeting || (appt.originalSlot.isFromMe(widget.myUserId));
    final borderColor = appt.isMeeting 
        ? Colors.white.withOpacity(0.4) 
        : Colors.blue.withOpacity(0.8);

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: color,
        border: hasBorder ? Border.all(color: borderColor, width: 1.0) : null,
      ),
      child: Center(
        child: _buildAppointmentContent(appt),
      ),
    );
  }

  Widget _buildAppointmentContent(ProcessedAppointment appt) {
    if (appt.isMeeting) {
      if (appt.isPast) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              appt.subject,
              style: const TextStyle(fontSize: 8, color: Colors.white60, decoration: TextDecoration.lineThrough),
              overflow: TextOverflow.ellipsis,
            ),
            const Text("Past", style: TextStyle(fontSize: 7, color: Colors.white38)),
          ],
        );
      }
      return Text(
        appt.subject,
        style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
      );
    }

    if (widget.calendarType == CalendarType.solo && appt.availability > 0) {
      return Text(
        "${(appt.availability * 100).toInt()}%",
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white70,
        ),
      );
    }

    if (widget.calendarType == CalendarType.group && 
        appt.originalSlot.type == 'others_busy' && 
        appt.originalSlot.freeCount != null) {
      return Text(
        "${appt.originalSlot.freeCount}/${appt.originalSlot.totalCount}",
        style: const TextStyle(
          fontSize: 9, 
          fontWeight: FontWeight.bold, 
          color: Colors.white70,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: widget.calendarType == CalendarType.group 
        ? [
            _legendItem(const Color(0xFF2E7D32), "Match"),
            _legendItem(Colors.blue, "Me"),
            _legendItem(Colors.orange, "Others"),
            _legendItem(Colors.purple, "Meeting"),
          ]
        : [
            _legendItem(Colors.green, "Free"),
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

  bool _isWithinWorkingHours(DateTime date) {
    final availability = widget.availability;
    if (availability.isEmpty) return true;

    final localDate = toUserLocal(date);
    final dayData = availability.firstWhere(
      (a) => a.dayOfWeek == (localDate.weekday - 1),
      orElse: () => availability[0],
    );

    if (!dayData.isEnabled) return false;

    final parts = dayData.startTime.split(':');
    final startVal = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    
    final endParts = dayData.endTime.split(':');
    final endVal = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

    final currentVal = localDate.hour * 60 + localDate.minute;
    return currentVal >= startVal && currentVal < endVal;
  }

  void _showNonWorkingHourWarning(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Selected time is outside of working hours.'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.orange,
      ),
    );
  }
}

class ProcessedAppointment extends Appointment {
  final TimeSlot originalSlot;
  final bool isMeeting;
  final Meeting? customMeeting;
  final double availability;
  final bool isPast;
  
  ProcessedAppointment({
    required super.startTime,
    required super.endTime,
    required super.color,
    super.subject,
    required this.originalSlot,
    this.isMeeting = false,
    this.customMeeting,
    this.availability = 0.0,
    this.isPast = false,
  });
}

class _MeetingDataSource extends CalendarDataSource {
  _MeetingDataSource(List<ProcessedAppointment> source) {
    appointments = source;
  }
}
