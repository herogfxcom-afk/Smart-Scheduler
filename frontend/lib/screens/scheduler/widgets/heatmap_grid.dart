import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import '../../../models/time_slot.dart';
import '../../../models/meeting.dart';
import '../../../utils/timezone_utils.dart';
import '../../../utils/calendar_processor.dart';
import '../../../core/telegram/telegram_service.dart';
import '../../../providers/availability_provider.dart';
import 'package:provider/provider.dart';

class HeatmapGrid extends StatefulWidget {
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
  State<HeatmapGrid> createState() => _HeatmapGridState();
}

class _HeatmapGridState extends State<HeatmapGrid> {
  final CalendarController _calendarController = CalendarController();
  late String? myUserId;

  @override
  void initState() {
    super.initState();
    myUserId = TelegramService().getUserId();
    
    // We don't need an explicit listener because context.watch handles it,
    // but just in case we need to trigger something else, we keep it simple.
  }

  void _refreshCalendar() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant HeatmapGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!DateUtils.isSameDay(oldWidget.selectedDay, widget.selectedDay)) {
      _calendarController.displayDate = widget.selectedDay;
    }
  }

  @override
  void dispose() {
    context.read<AvailabilityProvider>().removeListener(_refreshCalendar);
    _calendarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SfCalendar(
            key: ValueKey('sf_calendar_${context.watch<AvailabilityProvider>().lastUpdated.millisecondsSinceEpoch}'),
            controller: _calendarController,
            view: CalendarView.week,
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
            ),
            specialRegions: _getWorkingHoursRegions(context),
            timeRegionBuilder: _timeRegionBuilder,
            backgroundColor: Colors.transparent,

            headerHeight: 0, // We hide the default header to rely on the timeline week header
            dataSource: _MeetingDataSource(_buildAppointments()),
            appointmentBuilder: _appointmentBuilder,
            onTap: (CalendarTapDetails details) {
              if (details.targetElement == CalendarElement.calendarCell) {
                final date = details.date;
                if (date != null) {
                  // Only allow selection if the slot is in the future
                  if (date.isBefore(userNow())) return;

                  // Validate working hours
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
                // Don't allow selecting past slots
                if (appt.startTime.isBefore(userNow())) return;
                widget.onSlotSelected(appt.originalSlot);
              }
            },
          ),
        ),
        _buildLegend(),
      ],
    );
  }

  List<ProcessedAppointment> _buildAppointments() {
    final List<ProcessedAppointment> appointments = [];
    final now = userNow();

    // Add Meetings
    for (final meeting in widget.myMeetings) {
      final startLocal = toUserLocal(meeting.start);
      final endLocal = toUserLocal(meeting.end);
      
      appointments.add(ProcessedAppointment(
        startTime: startLocal,
        endTime: endLocal,
        color: Colors.purple.withOpacity(0.85),
        subject: meeting.title,
        originalSlot: TimeSlot(start: meeting.start, end: meeting.end, type: 'meeting'),
        isMeeting: true,
        customMeeting: meeting,
      ));
    }

    // Add Busy Slots / Free Slots
    for (final slot in widget.slots) {
      final startLocal = toUserLocal(slot.start);
      final endLocal = toUserLocal(slot.end);
      final color = _getSlotColor(slot);
      
      appointments.add(ProcessedAppointment(
        startTime: startLocal,
        endTime: endLocal,
        color: color,
        subject: '',
        originalSlot: slot,
        availability: slot.availability,
        isPast: endLocal.isBefore(now),
      ));
    }

    return appointments;
  }

  Color _getSlotColor(TimeSlot timeSlot) {
    if (widget.calendarType == CalendarType.solo) {
      if (timeSlot.availability == 1.0) return Colors.green.withOpacity(0.35);
      if (timeSlot.availability > 0.6) return Colors.green.withOpacity(0.2);
      if (timeSlot.availability > 0.0) return Colors.orange.withOpacity(0.2);
      return Colors.red.withOpacity(0.2);
    }
    
    // Group Colors
    if (timeSlot.isCommonSlot) return const Color(0xFF2E7D32).withOpacity(0.8);
    if (timeSlot.isFromMe(myUserId)) return Colors.blue.withOpacity(0.6);
    if (timeSlot.isFromOthers(myUserId)) return Colors.deepOrange.withOpacity(0.5);
    
    return Colors.white.withOpacity(0.05);
  }

  Widget _appointmentBuilder(BuildContext context, CalendarAppointmentDetails details) {
    final ProcessedAppointment appt = details.appointments.first;
    
    // Past events are darkened/grayed
    final isPast = appt.isPast;
    final color = isPast ? Colors.grey.withOpacity(0.4) : appt.color;
    
    // Border for meetings or my busy slots
    final hasBorder = appt.isMeeting || (appt.originalSlot.isFromMe(myUserId));
    final borderColor = appt.isMeeting 
        ? Colors.white.withOpacity(0.4) 
        : Colors.blue.withOpacity(0.8);

    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
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

    // Show percentage for solo calendar non-busy slots
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

  List<TimeRegion> _getWorkingHoursRegions(BuildContext context) {
    final availability = context.watch<AvailabilityProvider>().availability;
    if (availability.isEmpty) return [];

    final List<TimeRegion> regions = [];
    
    // Map backend day format (0=Monday) to RRule (MO)
    final rruleDays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

    for (var a in availability) {
      if (!a.isEnabled) continue;

      try {
        final startParts = a.startTime.split(':');
        final endParts = a.endTime.split(':');
        
        final startHour = int.parse(startParts[0]);
        final startMin = int.parse(startParts[1]);
        final endHour = int.parse(endParts[0]);
        final endMin = int.parse(endParts[1]);

        // We use a fixed date for the baseline of the recurring rule
        // Sunday Jan 5, 2025 was the start of a week
        // Monday Jan 6, 2025 starts the MO rule
        final baseDate = DateTime(2025, 1, 6 + a.dayOfWeek);

        regions.add(TimeRegion(
          startTime: DateTime(baseDate.year, baseDate.month, baseDate.day, startHour, startMin),
          endTime: DateTime(baseDate.year, baseDate.month, baseDate.day, endHour, endMin),
          recurrenceRule: 'FREQ=WEEKLY;BYDAY=${rruleDays[a.dayOfWeek]}',
          color: Colors.green.withOpacity(0.08),
          text: 'Working Hours',
          enablePointerInteraction: true,
        ));
      } catch (e) {
        debugPrint("Error creating time region: $e");
      }
    }
    return regions;
  }

  Widget _timeRegionBuilder(BuildContext context, TimeRegionDetails details) {
    return Container(
      decoration: BoxDecoration(
        color: details.region.color,
        border: Border.all(color: Colors.green.withOpacity(0.1), width: 0.5),
      ),
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.all(4),
      child: Text(
        details.region.text ?? '',
        style: TextStyle(
          fontSize: 8,
          color: Colors.green.withOpacity(0.5),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  bool _isWithinWorkingHours(DateTime date) {
    final availability = context.read<AvailabilityProvider>().availability;
    if (availability.isEmpty) return true; // Default to open if not loaded

    final dayData = availability.firstWhere(
      (a) => a.dayOfWeek == (date.weekday - 1), // DateTime weekday is 1-7, backend 0-6
      orElse: () => availability[0], // fallback
    );

    if (!dayData.isEnabled) return false;

    final parts = dayData.startTime.split(':');
    final startVal = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    
    final endParts = dayData.endTime.split(':');
    final endVal = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

    final currentVal = date.hour * 60 + date.minute;
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
