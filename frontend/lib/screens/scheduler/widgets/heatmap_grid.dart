import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import '../../../models/time_slot.dart';
import '../../../models/meeting.dart';
import '../../../utils/timezone_utils.dart';
import '../../../utils/calendar_processor.dart';
import '../../../core/telegram/telegram_service.dart';
import '../../../providers/availability_provider.dart';
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
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    _calendarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SfCalendar(
            key: ValueKey('sf_calendar_${widget.selectedDay.millisecondsSinceEpoch}_${widget.availability.length}_${getUserTimezone()}'),
            controller: _calendarController,
            view: CalendarView.week,
            timeZone: getUserTimezone(), // Sync with browser's IANA TZ instead of hardcoded UTC
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

    // Add Busy Slots / Free Slots
    for (final slot in widget.slots) {
      // Skip busy and others_busy slots to remove the unwanted "red bars" and noise
      // User only wants to see available matches/slots
      if (slot.type == 'busy' || slot.type == 'others_busy') continue;
      if (slot.availability == 0.0) continue;

      final startUtc = slot.start.isUtc ? slot.start : slot.start.toUtc();
      final endUtc = slot.end.isUtc ? slot.end : slot.end.toUtc();
      final color = _getSlotColor(slot);
      
      appointments.add(ProcessedAppointment(
        startTime: startUtc,
        endTime: endUtc,
        color: color,
        subject: '',
        originalSlot: slot,
        availability: slot.availability,
        isPast: endUtc.isBefore(now.toUtc()),
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
    if (timeSlot.isFromMe(widget.myUserId)) return Colors.blue.withOpacity(0.6);
    if (timeSlot.isFromOthers(widget.myUserId)) return Colors.deepOrange.withOpacity(0.5);
    
    return Colors.white.withOpacity(0.05);
  }

  Widget _appointmentBuilder(BuildContext context, CalendarAppointmentDetails details) {
    final ProcessedAppointment appt = details.appointments.first;
    
    // Past events are darkened/grayed
    final isPast = appt.isPast;
    final color = isPast ? Colors.grey.withOpacity(0.4) : appt.color;
    
    // Border for meetings or my busy slots
    final hasBorder = appt.isMeeting || (appt.originalSlot.isFromMe(widget.myUserId));
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

    // Show fractional availability for group partial matches
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
    if (availability.isEmpty) return true; // Default to open if not loaded

    // Use local time for boundary check (User wants 09:00 in their clock)
    final localDate = toUserLocal(date);
    
    final dayData = availability.firstWhere(
      (a) => a.dayOfWeek == (localDate.weekday - 1), // DateTime weekday is 1-7, backend 0-6
      orElse: () => availability[0], // fallback
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
