import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import '../../../models/time_slot.dart';
import '../../../models/meeting.dart';
import '../../../utils/timezone_utils.dart';
import '../../../utils/calendar_processor.dart';
import '../../../core/telegram/telegram_service.dart';

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
            key: const ValueKey('sf_calendar_heatmap'),
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
                  
                  // Construct a dummy TimeSlot for the selected cell
                  // We default to free type so the user can interact
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
    
    // Past events are darkened
    final isPast = appt.isPast;
    final color = isPast ? Colors.grey.withOpacity(0.3) : appt.color;
    
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
