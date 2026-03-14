import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../providers/scheduler_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/meeting_provider.dart';
import '../../providers/solo_provider.dart';
import '../../models/time_slot.dart';
import '../../models/meeting.dart';
import '../../utils/timezone_utils.dart';
import '../../utils/calendar_processor.dart';
import '../../utils/ics_exporter.dart';
import '../../providers/availability_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/availability.dart';
import 'widgets/heatmap_grid.dart';

class SchedulerScreen extends StatefulWidget {
  const SchedulerScreen({super.key});

  @override
  State<SchedulerScreen> createState() => _SchedulerScreenState();
}

class _SchedulerScreenState extends State<SchedulerScreen> {
  DateTime _selectedDay = userNow();
  bool _isHeatmapView = true;
  final List<String> _ignoredParticipantIds = [];

  @override
  void initState() {
    super.initState();
    _initDataLoading();
  }

  void _initDataLoading() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final groupProvider = context.read<GroupProvider>();
      
      // Listen for participant changes to update slots
      groupProvider.addListener(_onGroupChanged);
      
      // Initial sync if ID is already there
      if (groupProvider.chatId != null) {
        groupProvider.syncWithGroup();
      }
    });
  }

  List<int> _lastFetchedParticipantIds = [];
  bool _isFetchingSlots = false;

  void _onGroupChanged() {
    if (!mounted) return;
    final groupProvider = context.read<GroupProvider>();
    final scheduler = context.read<SchedulerProvider>();
    
    if (groupProvider.participants.isNotEmpty) {
      final ids = groupProvider.participants.map((p) => p.telegramId).toList();
      ids.sort(); // Sort to ensure consistent comparison
      
      // Prevent over-fetching: check if the participants list actually changed
      if (const ListEquality().equals(ids, _lastFetchedParticipantIds) && scheduler.suggestedSlots.isNotEmpty) {
        return; 
      }
      
      if (_isFetchingSlots) return; // Prevent concurrent identical requests
      _isFetchingSlots = true;
      _lastFetchedParticipantIds = ids;
      
      print("DEBUG: Participants updated, fetching slots for: $ids in group: ${groupProvider.chatId}");
      // Always fetch myMeetings first so purple coloring is correct after reload
      context.read<MeetingProvider>().fetchMyMeetings().then((_) {
        // avoid running if unmounted
        if (mounted) {
          scheduler.fetchCommonSlots(ids, chatId: groupProvider.chatId).whenComplete(() {
            if (mounted) _isFetchingSlots = false;
          });
        } else {
          _isFetchingSlots = false;
        }
      });
    }
  }

  @override
  void dispose() {
    // Remove listener safely
    try {
      context.read<GroupProvider>().removeListener(_onGroupChanged);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheduler = context.watch<SchedulerProvider>();
    final groupProvider = context.watch<GroupProvider>();
    
    if (groupProvider.chatId == null && !groupProvider.isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text("Доступность участников")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.group_off, size: 64, color: Colors.grey),
                const SizedBox(height: 32),
                const SizedBox(height: 16),
                const Text(
                  "Группа не определена.\nИспользуйте кнопку Magic Sync в Telegram или введите данные ниже.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        groupProvider.setChatId(val.trim());
                      }
                    },
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: "ID группы или ссылка-приглашение",
                      hintStyle: TextStyle(color: Colors.white38),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => context.pop(),
                      child: const Text("Домой"),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () {
                         context.pop();
                      },
                      child: const Text("Ручной ввод"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    final Map<String, List<TimeSlot>> groupedSlots = {};
    for (var slot in scheduler.suggestedSlots) {
      final localStart = toUserLocal(slot.start);
      final dateKey = "${localStart.year}-${localStart.month}-${localStart.day}";
      groupedSlots.putIfAbsent(dateKey, () => []).add(slot);
    }

    final dayKey = "${_selectedDay.year}-${_selectedDay.month}-${_selectedDay.day}";
    final slotsForDay = groupedSlots[dayKey] ?? [];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Доступность команды v6.1.0"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh sync",
            onPressed: () {
               context.read<GroupProvider>().syncWithGroup();
            },
          ),
          IconButton(
            icon: Icon(_isHeatmapView ? Icons.calendar_view_day : Icons.grid_on),
            onPressed: () => setState(() => _isHeatmapView = !_isHeatmapView),
          ),
        ],
      ),
      body: Column(
        children: [
          // Participant Horizontal List (with Toggle)
          Container(
            height: 100,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: groupProvider.participants.length,
              itemBuilder: (context, index) {
                final p = groupProvider.participants[index];
                final isIgnored = _ignoredParticipantIds.contains(p.id.toString());
                
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isIgnored) {
                        _ignoredParticipantIds.remove(p.id.toString());
                      } else {
                        _ignoredParticipantIds.add(p.id.toString());
                      }
                    });
                    // Re-fetch slots
                    final availableIds = context.read<GroupProvider>().participants
                      .map((p) => p.telegramId)
                      .where((id) => !_ignoredParticipantIds.contains(id.toString()))
                      .toList();
                    scheduler.findBestTime(availableIds, chatId: groupProvider.chatId);
                  },
                  child: Container(
                    width: 70,
                    margin: const EdgeInsets.only(right: 12),
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isIgnored ? Colors.grey : (p.isSynced ? Colors.green : Colors.orange),
                                  width: 2,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.grey[900],
                                backgroundImage: p.photoUrl != null ? NetworkImage(p.photoUrl!) : null,
                                child: p.photoUrl == null ? const Icon(Icons.person, color: Colors.white24) : null,
                              ),
                            ),
                            if (isIgnored)
                              const Positioned(
                                right: 0,
                                top: 0,
                                child: CircleAvatar(
                                  radius: 8,
                                  backgroundColor: Colors.black,
                                  child: Icon(Icons.block, size: 10, color: Colors.red),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.firstName ?? "User",
                          style: TextStyle(
                            fontSize: 10,
                            color: isIgnored ? Colors.grey : Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Day Selector
          SizedBox(
            height: 70,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 14, // 2 weeks
              itemBuilder: (context, index) {
                final day = userNow().add(Duration(days: index));
                final isSelected = DateUtils.isSameDay(day, _selectedDay);
                
                return GestureDetector(
                  onTap: () => setState(() => _selectedDay = day),
                  child: Container(
                    width: 50,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('E').format(day),
                          style: TextStyle(fontSize: 10, color: isSelected ? Colors.white : Colors.grey),
                        ),
                        Text(
                          day.day.toString(),
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.white70),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 16),

          // Main View (Heatmap / List)
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF121212),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: scheduler.isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _isHeatmapView
                  ? HeatmapGrid(
                      slots: scheduler.suggestedSlots,
                      selectedDay: _selectedDay,
                      availability: context.watch<AvailabilityProvider>().availability,
                      myMeetings: context.watch<MeetingProvider>().meetings,
                      onSlotSelected: (slot) => _handleSlotSelected(context, scheduler, slot),
                      myUserId: context.read<AuthProvider>().user?.id.toString() ?? '',
                      calendarType: CalendarType.group,
                    )
                  : _buildListSlots(slotsForDay, scheduler),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ElevatedButton.icon(
            onPressed: () => _showManualBooking(context, scheduler),
            icon: const Icon(Icons.calendar_today, color: Colors.white),
            label: Text(
              "Забронировать лучшее время",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ),
    );
  }

  void _showManualBooking(BuildContext context, SchedulerProvider scheduler) async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: userNow(),
      lastDate: userNow().add(const Duration(days: 90)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Colors.blue),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Colors.blue),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute).toUtc();
    final end = start.add(const Duration(hours: 1));

    final manualSlot = TimeSlot(
      start: start,
      end: end,
      type: 'match',
      availability: 1.0,
    );
    _showBookingOptions(context, scheduler, manualSlot);
  }

  Widget _buildListSlots(List<TimeSlot> slotsForDay, SchedulerProvider scheduler) {
    if (slotsForDay.isEmpty) {
      return const Center(child: Text("No common free slots found for this day."));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: slotsForDay.length,
      itemBuilder: (context, index) {
        final slot = slotsForDay[index];
        return _buildSlotCard(slot, scheduler);
      },
    );
  }

  Widget _buildSlotCard(TimeSlot slot, SchedulerProvider scheduler) {
    final localStart = toUserLocal(slot.start);
    final localEnd = toUserLocal(slot.end);
    final start = "${localStart.hour}:${localStart.minute.toString().padLeft(2, '0')}";
    final end = "${localEnd.hour}:${localEnd.minute.toString().padLeft(2, '0')}";
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: slot.isFullMatch ? const Color(0xFF00E676) : const Color(0xFFFF9100),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (slot.isFullMatch ? const Color(0xFF00E676) : const Color(0xFFFF9100)).withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _handleSlotSelected(context, scheduler, slot),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (slot.isFullMatch ? const Color(0xFF00E676) : const Color(0xFFFF9100)).withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: (slot.isFullMatch ? const Color(0xFF00E676) : const Color(0xFFFF9100)).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  slot.isFullMatch ? Icons.verified : Icons.group_outlined,
                  color: slot.isFullMatch ? const Color(0xFF00E676) : const Color(0xFFFF9100),
                  size: 32,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "$start - $end",
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      slot.isFullMatch ? "EVERYONE IS FREE" : "SOMEONE IS BUSY",
                      style: TextStyle(
                        color: slot.isFullMatch ? const Color(0xFF00E676) : const Color(0xFFFF9100),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSlotSelected(BuildContext context, SchedulerProvider scheduler, TimeSlot slot) {
    if (slot.isFullMatch) {
      _showBookingOptions(context, scheduler, slot);
      return;
    }

    if (slot.isMyBusy) {
      final matchedMeeting = context.read<MeetingProvider>().meetings.firstWhereOrNull((m) {
        final mStart = toUserLocal(m.start);
        final mEnd = toUserLocal(m.end);
        final sStart = toUserLocal(slot.start);
        return (sStart.isAtSameMomentAs(mStart) || sStart.isAfter(mStart)) && sStart.isBefore(mEnd);
      });

      if (matchedMeeting != null && matchedMeeting.isCreator) {
        _showMeetingDetailsOptions(context, scheduler, matchedMeeting.toJson());
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('В это время у вас запланированы личные дела (внешний календарь).')),
      );
      return;
    }

    if (slot.isOthersBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Один или несколько участников заняты в это время.')),
      );
      return;
    }
  }

  void _showMeetingDetailsOptions(BuildContext context, SchedulerProvider scheduler, Map<String, dynamic> meetingData) {
    final title = meetingData['title'] ?? 'Встреча';
    final meetingId = meetingData['id'];
    final isCancelled = meetingData['is_cancelled'] == true;
    final isCreator = meetingData['is_creator'] == true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        bool isProcessing = false;
        return StatefulBuilder(
          builder: (context, setState) => Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isCancelled ? Icons.event_busy : Icons.event_note, 
                  color: isCancelled ? Colors.redAccent : Colors.blue, 
                  size: 48
                ),
                const SizedBox(height: 16),
                Text(
                  isCancelled ? "ОТМЕНЕНА: $title" : title,
                  style: TextStyle(
                    color: isCancelled ? Colors.redAccent : Colors.white, 
                    fontSize: 20, 
                    fontWeight: FontWeight.bold,
                    decoration: isCancelled ? TextDecoration.lineThrough : null,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (isCancelled) ...[
                  const SizedBox(height: 8),
                  const Text(
                    "Организатор отменил эту встречу. Подтвердите удаление, чтобы очистить ваш календарь.",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : () async {
                      setState(() => isProcessing = true);
                      
                      final bool success;
                      if (isCancelled) {
                        success = await scheduler.confirmCancelMeeting(meetingId);
                      } else {
                        success = await scheduler.deleteMeeting(meetingId);
                      }
                      
                      if (context.mounted) {
                        Navigator.pop(context);
                        if (success) {
                          context.read<MeetingProvider>().fetchMyMeetings();
                          context.read<SoloProvider>().fetchSoloSlots();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isCancelled ? 'Встреча удалена из списка' : 'Встреча успешно отменена'), 
                              backgroundColor: Colors.green
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isCancelled ? 'Ошибка удаления' : 'Ошибка отмены встречи'), 
                              backgroundColor: Colors.red
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCancelled ? Colors.orange.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                      foregroundColor: isCancelled ? Colors.orangeAccent : Colors.redAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      side: BorderSide(color: isCancelled ? Colors.orangeAccent : Colors.redAccent, width: 1),
                    ),
                    child: isProcessing
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: isCancelled ? Colors.orangeAccent : Colors.redAccent, strokeWidth: 2))
                      : Text(
                          isCancelled ? 'Подтвердить удаление' : (isCreator ? 'Отменить встречу' : 'Покинуть встречу'), 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                        ),
                  ),
                ),
                const SizedBox(height: 12),
                if (!isCancelled)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final m = Meeting.fromJson(meetingData);
                        IcsExporter.exportMeeting(m);
                      },
                    icon: const Icon(Icons.apple),
                    label: const Text('Добавить в Apple Calendar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Закрыть', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showBookingOptions(BuildContext context, SchedulerProvider scheduler, TimeSlot slot) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime startTime = toUserLocal(slot.start);
    DateTime endTime = toUserLocal(slot.end);
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Новая встреча",
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                // Date Selection
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: startTime,
                      firstDate: userNow(),
                      lastDate: userNow().add(const Duration(days: 90)),
                      builder: (ctx, child) => Theme(
                        data: ThemeData.dark().copyWith(
                          colorScheme: const ColorScheme.dark(primary: Colors.blue),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setState(() {
                        startTime = DateTime(picked.year, picked.month, picked.day, startTime.hour, startTime.minute);
                        endTime = DateTime(picked.year, picked.month, picked.day, endTime.hour, endTime.minute);
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.blue, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          DateFormat('EEEE, d MMMM').format(startTime),
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        const Spacer(),
                        const Icon(Icons.arrow_drop_down, color: Colors.white54),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "Название встречи",
                    labelStyle: const TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: "Описание (необязательно)",
                    labelStyle: const TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Icon(Icons.access_time, color: Colors.blueAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(startTime),
                          );
                          if (picked != null) {
                            setState(() {
                              startTime = DateTime(startTime.year, startTime.month, startTime.day, picked.hour, picked.minute);
                              if (endTime.isBefore(startTime)) {
                                endTime = startTime.add(const Duration(hours: 1));
                              }
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            DateFormat('HH:mm').format(startTime),
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text("-", style: TextStyle(color: Colors.white)),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(endTime),
                          );
                          if (picked != null) {
                            setState(() {
                              endTime = DateTime(endTime.year, endTime.month, endTime.day, picked.hour, picked.minute);
                              if (endTime.isBefore(startTime)) {
                                startTime = endTime.subtract(const Duration(hours: 1));
                              }
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            DateFormat('HH:mm').format(endTime),
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : () async {
                      if (titleController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Введите название встречи")),
                        );
                        return;
                      }

                      setState(() => isLoading = true);
                      
                      // Create a new TimeSlot based on selected interactive times
                      final finalSlot = TimeSlot(
                        start: startTime.toUtc(),
                        end: endTime.toUtc(),
                        type: slot.type,
                        availability: slot.availability,
                      );

                      // FIX: Collect all participants for invitation (excluding self)
                      final groupProvider = context.read<GroupProvider>();
                      final List<int> invitedTelegramIds = groupProvider.participants
                          .map((p) => p.telegramId)
                          .where((id) => id != context.read<AuthProvider>().user?.telegramId)
                          .toList();

                      final success = await scheduler.createMeeting(
                        title: titleController.text.trim(),
                        description: descriptionController.text.trim(),
                        slot: finalSlot,
                        chatId: groupProvider.chatId,
                        invitedTelegramIds: invitedTelegramIds,
                      );

                      if (context.mounted) {
                        Navigator.pop(context);
                        if (success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Встреча успешно создана!"), backgroundColor: Colors.green),
                          );
                          context.read<MeetingProvider>().fetchMyMeetings();
                          context.read<SoloProvider>().fetchSoloSlots(); // Keep Solo slots visually synced
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Ошибка при создании встречи"), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Подтвердить", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Отмена", style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
