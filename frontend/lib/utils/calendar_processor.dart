import 'package:flutter/material.dart';
import '../models/time_slot.dart';
import '../models/meeting.dart';
import 'timezone_utils.dart';
import 'slot_merger.dart';

enum CalendarType {
  solo,
  group,
}

class ProcessedSlot {
  final TimeSlot originalSlot;
  final bool isMeeting;
  final Meeting? meeting;

  ProcessedSlot({
    required this.originalSlot,
    this.isMeeting = false,
    this.meeting,
  });
}

class CalendarProcessor {
  final List<TimeSlot> slots;
  final DateTime selectedDay;
  final List<Meeting> meetings;
  final CalendarType type;
  
  final int _minHour = 7;
  final int _maxHour = 24;

  late Map<int, Map<int, List<ProcessedSlot>>> _gridData;
  late DateTime _gridStart;

  final String? myUserId;

  CalendarProcessor({
    required this.slots,
    required this.selectedDay,
    this.meetings = const [],
    required this.type,
    this.myUserId,
  }) {
    _initialize();
  }

  void _initialize() {
    final now = userNow();
    final today = DateTime(now.year, now.month, now.day);
    final int dayOffset = selectedDay.difference(today).inDays;
    
    _gridStart = dayOffset >= 7 ? today.add(const Duration(days: 7)) : today;
    _buildGrid(myUserId);
  }

  DateTime get gridStart => _gridStart;
  int get minHour => _minHour;
  int get maxHour => _maxHour;

  List<ProcessedSlot> getSlots(int hour, int dayIndex) {
    return _gridData[hour]?[dayIndex] ?? [];
  }

  void _buildGrid(String? myUserId) {
    _gridData = {};
    
    // 1. Initialize empty grid
    for (int hour = _minHour; hour < _maxHour; hour++) {
      _gridData[hour] = {};
      for (int i = 0; i < 7; i++) {
        _gridData[hour]![i] = [];
      }
    }
    
    // 2. Add raw slots
    for (final slot in slots) {
      _addSlotToGrid(slot);
    }
    
    // 3. Add meetings if Group type
    if (type == CalendarType.group) {
      _addMeetingsToGrid();
    }
    
    // 4. Post-processing: Sorting and Prioritization
    _finalizeGrid(myUserId);
  }

  void _addSlotToGrid(TimeSlot slot) {
    final localStart = toUserLocal(slot.start);
    final localEnd = toUserLocal(slot.end);
    
    final int startDiff = DateUtils.dateOnly(localStart).difference(_gridStart).inDays;
    final int endDiff = DateUtils.dateOnly(localEnd).difference(_gridStart).inDays;

    for (int currentDiff = startDiff; currentDiff <= endDiff; currentDiff++) {
      if (currentDiff >= 0 && currentDiff < 7) {
        int startH = _minHour;
        int endH = _maxHour - 1;

        if (currentDiff == startDiff) startH = localStart.hour.clamp(_minHour, _maxHour - 1);
        if (currentDiff == endDiff) {
          endH = localEnd.hour;
          if (localEnd.minute == 0 && endH > startH) endH -= 1;
          endH = endH.clamp(_minHour, _maxHour - 1);
        }

        for (int h = startH; h <= endH; h++) {
          _gridData[h]![currentDiff]!.add(ProcessedSlot(originalSlot: slot));
        }
      }
    }
  }

  void _addMeetingsToGrid() {
    for (final meeting in meetings) {
      final mStart = toUserLocal(meeting.start);
      final mEnd = toUserLocal(meeting.end);
      
      final int startDiff = DateUtils.dateOnly(mStart).difference(_gridStart).inDays;
      final int endDiff = DateUtils.dateOnly(mEnd).difference(_gridStart).inDays;

      for (int currentDiff = startDiff; currentDiff <= endDiff; currentDiff++) {
        if (currentDiff >= 0 && currentDiff < 7) {
          int startH = mStart.hour.clamp(_minHour, _maxHour - 1);
          int endH = mEnd.hour;
          if (mEnd.minute == 0 && endH > startH) endH -= 1;
          endH = endH.clamp(_minHour, _maxHour - 1);

          for (int h = startH; h <= endH; h++) {
            // Check if meeting spans this hour
            final cellST = DateTime(_gridStart.year, _gridStart.month, _gridStart.day + currentDiff, h);
            final cellET = cellST.add(const Duration(hours: 1));
            
            if (mStart.isBefore(cellET) && mEnd.isAfter(cellST)) {
              _gridData[h]![currentDiff]!.add(ProcessedSlot(
                originalSlot: TimeSlot(start: meeting.start, end: meeting.end, type: 'meeting'),
                isMeeting: true,
                meeting: meeting,
              ));
            }
          }
        }
      }
    }
  }

  void _finalizeGrid(String? myUserId) {
    for (int hour = _minHour; hour < _maxHour; hour++) {
      for (int day = 0; day < 7; day++) {
        final cellSlots = _gridData[hour]![day]!;
        if (cellSlots.isEmpty) continue;

        // Sort: Meetings on top, then MyBusy, then Priority
        cellSlots.sort((a, b) {
          if (a.isMeeting && !b.isMeeting) return 1;
          if (!a.isMeeting && b.isMeeting) return -1;
          
          final aMe = a.originalSlot.isFromMe(myUserId);
          final bMe = b.originalSlot.isFromMe(myUserId);
          if (aMe && !bMe) return 1;
          if (!aMe && bMe) return -1;
          
          return a.originalSlot.priority.compareTo(b.originalSlot.priority);
        });

        if (type == CalendarType.solo) {
           if (cellSlots.length > 1) {
             _gridData[hour]![day] = [cellSlots.last]; 
           }
        } else {
          // GROUP: Overlap filtering
          // If I am busy in this cell, don't show that others are also busy (Keep it simpler)
          final hasMine = cellSlots.any((s) => s.originalSlot.isFromMe(myUserId));
          if (hasMine) {
            _gridData[hour]![day] = cellSlots.where((s) => 
               s.isMeeting || s.originalSlot.isFromMe(myUserId)
            ).toList();
          }
        }
      }
    }
  }

  Color getSlotColor(ProcessedSlot slot, String? myUserId) {
    if (slot.isMeeting) {
      return Colors.purple.withOpacity(0.85);
    }
    
    final timeSlot = slot.originalSlot;
    
    if (type == CalendarType.solo) {
      if (timeSlot.availability == 1.0) return Colors.green.withOpacity(0.35);
      if (timeSlot.availability > 0.6) return Colors.green.withOpacity(0.2);
      if (timeSlot.availability > 0.0) return Colors.orange.withOpacity(0.2);
      return Colors.red.withOpacity(0.2);
    }
    
    // Group Colors using ID-aware identification
    if (timeSlot.isCommonSlot)      return const Color(0xFF2E7D32).withOpacity(0.8);
    if (timeSlot.isFromMe(myUserId))     return Colors.blue.withOpacity(0.6);
    if (timeSlot.isFromOthers(myUserId)) return Colors.deepOrange.withOpacity(0.5);
    
    return Colors.white.withOpacity(0.05);
  }

  String getSlotTooltip(ProcessedSlot ps, String? myUserId) {
    if (ps.isMeeting) return "Meeting: ${ps.meeting?.title ?? 'No Title'}";
    final slot = ps.originalSlot;
    if (slot.isCommonSlot) return "Common Free Time (All ready)";
    if (slot.isFromMe(myUserId)) return "You are busy";
    if (slot.sourceUserId != null) {
      // Ideally we'd have a userId -> Name map, but for now we indicate it's someone specific
      return "Participant busy (ID: ${slot.sourceUserId})";
    }
    return "Someone is busy";
  }
}
