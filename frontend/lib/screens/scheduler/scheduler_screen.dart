import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../providers/scheduler_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/meeting_provider.dart';
import '../../core/telegram/telegram_service.dart';
import '../../models/time_slot.dart';
import '../../models/meeting.dart';
import 'widgets/heatmap_grid.dart';
import 'widgets/heatmap_grid.dart';

class SchedulerScreen extends StatefulWidget {
  const SchedulerScreen({super.key});

  @override
  State<SchedulerScreen> createState() => _SchedulerScreenState();
}

class _SchedulerScreenState extends State<SchedulerScreen> {
  DateTime _selectedDay = DateTime.now();
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

  void _onGroupChanged() {
    if (!mounted) return;
    final groupProvider = context.read<GroupProvider>();
    final scheduler = context.read<SchedulerProvider>();
    
    if (groupProvider.participants.isNotEmpty) {
      final ids = groupProvider.participants.map((p) => p.telegramId).toList();
      print("DEBUG: Participants updated, fetching slots for: $ids in group: ${groupProvider.chatId}");
      // Always fetch myMeetings first so purple coloring is correct after reload
      context.read<MeetingProvider>().fetchMyMeetings().then((_) {
        // avoid running if unmounted
        if (mounted) scheduler.fetchCommonSlots(ids, chatId: groupProvider.chatId);
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
                const SizedBox(height: 16),
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
      final dateKey = "${slot.start.year}-${slot.start.month}-${slot.start.day}";
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
          // Permanent "Book Meeting" button
          IconButton(
            icon: const Icon(Icons.event_available, color: Colors.blue),
            tooltip: "Book a Meeting",
            onPressed: () => _showManualBooking(context, scheduler),
          ),
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
                final day = DateTime.now().add(Duration(days: index));
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
                      ignoredParticipantIds: _ignoredParticipantIds,
                      myMeetings: context.watch<MeetingProvider>().meetings,
                      onSlotSelected: (slot) => _handleSlotSelected(context, scheduler, slot),
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
            onPressed: () {
              if (scheduler.suggestedSlots.isNotEmpty) {
                _showBookingOptions(context, scheduler, scheduler.suggestedSlots.first);
              } else {
                _showManualBooking(context, scheduler);
              }
            },
            icon: const Icon(Icons.calendar_today, color: Colors.white),
            label: Text(
              scheduler.suggestedSlots.isNotEmpty ? "Забронировать лучшее время" : "Назначить встречу",
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
      floatingActionButton: null,
    );
  }

  /// Opens a manual date/time picker so users can book even without Google Calendar data.
  void _showManualBooking(BuildContext context, SchedulerProvider scheduler) async {
    // Step 1: Date picker
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Colors.blue),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    // Step 2: Time picker
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

    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
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
    final localStart = slot.start.toLocal();
    final localEnd = slot.end.toLocal();
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
        onTap: () => _showBookingOptions(context, scheduler, slot),
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
    // 1. If it's a perfect match, proceed to booking
    if (slot.isFullMatch) {
      _showBookingOptions(context, scheduler, slot);
      return;
    }

    // 2. If I am busy, check if it's an app-created meeting I can delete
    if (slot.isMyBusy) {
      final utcStart = slot.start.toUtc().toIso8601String().replaceAll('.000', '');
      
      // Look for a matching meeting in myMeetings
      final matchedMeeting = context.read<MeetingProvider>().meetings.firstWhereOrNull(
        (m) {
          final mStart = m.start.toLocal();
          final mEnd = m.end.toLocal();
          final sStart = slot.start.toLocal();
          
          // slot starts exactly at or after meeting start AND slot starts strictly before meeting end
          return (sStart.isAtSameMomentAs(mStart) || sStart.isAfter(mStart)) && sStart.isBefore(mEnd);
        },
      );

      if (matchedMeeting != null && matchedMeeting.isCreator) {
        _showMeetingDetailsOptions(context, scheduler, matchedMeeting.toJson());
        return;
      }

      // If no match found or not creator, it's a personal Google event
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('В это время у вас запланированы личные дела (внешний календарь).')),
      );
      return;
    }

    // 3. Someone else is busy
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

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        bool isDeleting = false;
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
                const Icon(Icons.event_note, color: Colors.blue, size: 48),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isDeleting ? null : () async {
                      setState(() => isDeleting = true);
                      final success = await scheduler.deleteMeeting(meetingId);
                      if (context.mounted) {
                        Navigator.pop(context);
                        if (success) {
                          context.read<MeetingProvider>().fetchMyMeetings();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Встреча успешно удалена'), backgroundColor: Colors.green),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ошибка удаления встречи'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withOpacity(0.2),
                      foregroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      side: const BorderSide(color: Colors.redAccent, width: 1),
                    ),
                    child: isDeleting 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 2))
                      : const Text('Отменить встречу', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Назад', style: TextStyle(color: Colors.grey, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showBookingOptions(BuildContext context, 
      SchedulerProvider scheduler, TimeSlot slot) {
    
    DateTime startTime = slot.start.toLocal();
    DateTime endTime = slot.end.toLocal();
    final titleController = TextEditingController();
    final locationController = TextEditingController();
    bool hasPickedTime = false;
    bool isLoading = false;
    bool isOnline = true; // Default to online (video call)

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          
          bool canSubmit = titleController.text.trim().isNotEmpty 
              && hasPickedTime 
              && !isLoading;

          return Container(
            margin: EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            decoration: BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ручка
                Container(
                  margin: EdgeInsets.only(top: 12, bottom: 8),
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Color(0xFF404040),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Заголовок
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 8, 12),
                  child: Row(
                    children: [
                      Icon(Icons.event_rounded, 
                          color: Color(0xFF4A90E2), size: 22),
                      SizedBox(width: 10),
                      Text('Новая встреча',
                        style: TextStyle(color: Colors.white, 
                            fontSize: 18, fontWeight: FontWeight.w600)),
                      Spacer(),
                      IconButton(
                        icon: Icon(Icons.close, color: Color(0xFF707070)),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Divider(color: Color(0xFF2A2A2A), height: 1),
                // Поля формы
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    children: [
                      // Поле названия
                      TextField(
                        controller: titleController,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(color: Colors.white, fontSize: 20,
                            fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: 'Название встречи',
                          hintStyle: TextStyle(color: Color(0xFF505050), 
                              fontSize: 20),
                          border: InputBorder.none,
                        ),
                      ),
                      SizedBox(height: 8),
                      // Дата
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: startTime,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now()
                                .add(Duration(days: 365)),
                            builder: (ctx, child) => Theme(
                              data: Theme.of(ctx).copyWith(
                                colorScheme: ColorScheme.dark(
                                  primary: Color(0xFF4A90E2),
                                  surface: Color(0xFF252525),
                                ),
                              ),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            setState(() {
                              final diff = endTime.difference(startTime);
                              startTime = DateTime(picked.year, 
                                  picked.month, picked.day,
                                  startTime.hour, startTime.minute);
                              endTime = startTime.add(diff);
                            });
                          }
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today_rounded,
                                  color: Color(0xFF606060), size: 20),
                              SizedBox(width: 12),
                              Text(
                                DateFormat('EEEE, d MMMM yyyy')
                                    .format(startTime),
                                style: TextStyle(color: Color(0xFFD0D0D0),
                                    fontSize: 15),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Время (Отдельные кнопки для Start и End)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.schedule_rounded, color: Color(0xFF606060), size: 20),
                            SizedBox(width: 12),
                            
                            // Начало
                            InkWell(
                              onTap: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.fromDateTime(startTime),
                                  builder: (ctx, child) => Theme(
                                    data: Theme.of(ctx).copyWith(
                                      colorScheme: ColorScheme.dark(
                                        primary: Color(0xFF4A90E2),
                                        surface: Color(0xFF252525),
                                      ),
                                    ),
                                    child: child!,
                                  ),
                                );
                                if (picked != null) {
                                  setState(() {
                                    hasPickedTime = true;
                                    startTime = DateTime(startTime.year,
                                        startTime.month, startTime.day,
                                        picked.hour, picked.minute);
                                    // Авто-правка конца, если он стал раньше начала
                                    if (endTime.isBefore(startTime)) {
                                      endTime = startTime.add(Duration(hours: 1));
                                    }
                                  });
                                }
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Color(0xFF2A2A2A),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  DateFormat('HH:mm').format(startTime),
                                  style: TextStyle(
                                      color: Color(0xFF4A90E2),
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('—', style: TextStyle(color: Color(0xFF606060))),
                            ),
                            
                            // Конец
                            InkWell(
                              onTap: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.fromDateTime(endTime),
                                  builder: (ctx, child) => Theme(
                                    data: Theme.of(ctx).copyWith(
                                      colorScheme: ColorScheme.dark(
                                        primary: Color(0xFF4A90E2),
                                        surface: Color(0xFF252525),
                                      ),
                                    ),
                                    child: child!,
                                  ),
                                );
                                if (picked != null) {
                                  setState(() {
                                    hasPickedTime = true;
                                    final newEnd = DateTime(endTime.year,
                                        endTime.month, endTime.day,
                                        picked.hour, picked.minute);
                                    
                                    // Защита от выбора времени конца ДО времени начала
                                    if (newEnd.isAfter(startTime)) {
                                      endTime = newEnd;
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Конец встречи не может быть раньше начала!'),
                                          backgroundColor: Colors.red,
                                        )
                                      );
                                    }
                                  });
                                }
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Color(0xFF2A2A2A),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  DateFormat('HH:mm').format(endTime),
                                  style: TextStyle(
                                      color: Color(0xFF4A90E2),
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16),

                      // Тип встречи: Online / Offline
                      Container(
                        decoration: BoxDecoration(
                          color: Color(0xFF252525),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: EdgeInsets.all(4),
                        child: Row(
                          children: [
                            // Online
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => isOnline = true),
                                child: AnimatedContainer(
                                  duration: Duration(milliseconds: 200),
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isOnline ? Color(0xFF4A90E2) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.videocam_rounded,
                                          color: isOnline ? Colors.white : Colors.grey,
                                          size: 18),
                                      SizedBox(width: 6),
                                      Text('Онлайн',
                                          style: TextStyle(
                                            color: isOnline ? Colors.white : Colors.grey,
                                            fontWeight: isOnline ? FontWeight.w600 : FontWeight.normal,
                                          )),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Offline
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => isOnline = false),
                                child: AnimatedContainer(
                                  duration: Duration(milliseconds: 200),
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: !isOnline ? Color(0xFF27AE60) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.location_on_rounded,
                                          color: !isOnline ? Colors.white : Colors.grey,
                                          size: 18),
                                      SizedBox(width: 6),
                                      Text('Оффлайн',
                                          style: TextStyle(
                                            color: !isOnline ? Colors.white : Colors.grey,
                                            fontWeight: !isOnline ? FontWeight.w600 : FontWeight.normal,
                                          )),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Поле адреса (только для оффлайн)
                      if (!isOnline) ...[
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.place_rounded, color: Color(0xFF606060), size: 20),
                            SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: locationController,
                                style: TextStyle(color: Colors.white, fontSize: 15),
                                decoration: InputDecoration(
                                  hintText: 'Адрес или место встречи',
                                  hintStyle: TextStyle(color: Color(0xFF505050)),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Divider(color: Color(0xFF2A2A2A)),
                      ],

                      SizedBox(height: 20),
                    ],
                  ),
                ),
                // Кнопка
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: canSubmit ? () async {
                        setState(() => isLoading = true);
                        final updatedSlot = TimeSlot(
                            start: startTime.toUtc(), 
                            end: endTime.toUtc());
                        final groupProvider = context.read<GroupProvider>();
                        
                        // Collect IDs of participants who are NOT ignored
                        final invitedIds = groupProvider.participants
                            .where((p) => !_ignoredParticipantIds.contains(p.id.toString()))
                            .map((p) => p.telegramId)
                            .toList();

                        final success = await scheduler.createMeeting(
                          title: titleController.text.trim(),
                          slot: updatedSlot,
                          invitedTelegramIds: invitedIds,
                          chatId: groupProvider.chatId,
                          meetingType: isOnline ? 'online' : 'offline',
                          location: isOnline ? null : locationController.text.trim(),
                        );
                        setState(() => isLoading = false);
                        if (success && context.mounted) {
                          // Refresh meeting list to show the new meeting (purple highlights etc)
                          context.read<MeetingProvider>().fetchMyMeetings();
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✅ Встреча забронирована!'),
                              backgroundColor: Color(0xFF2ECC71),
                            ),
                          );
                        }
                      } : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canSubmit 
                            ? Color(0xFF4A90E2) 
                            : Color(0xFF2A2A2A),
                        foregroundColor: canSubmit 
                            ? Colors.white 
                            : Color(0xFF505050),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: isLoading
                        ? SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : Text('Забронировать',
                            style: TextStyle(fontSize: 16,
                                fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }
}
