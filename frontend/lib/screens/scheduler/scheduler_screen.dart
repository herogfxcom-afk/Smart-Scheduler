import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../providers/scheduler_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/sync_provider.dart';
import '../../core/telegram/telegram_service.dart';
import '../../models/time_slot.dart';
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
      print("DEBUG: Participants updated, fetching slots for: $ids");
      scheduler.fetchCommonSlots(ids);
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
        title: const Text("Доступность команды"),
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
                    scheduler.findBestTime(availableIds);
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
                      onSlotSelected: (slot) => _showBookingOptions(context, scheduler, slot),
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

  /// Shows a high-fidelity Google-style booking form.
  void _showBookingOptions(
    BuildContext context,
    SchedulerProvider scheduler,
    TimeSlot slot,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // full-height sheet
      backgroundColor: Colors.transparent,
      builder: (_) => BookingFormSheet(
        initialSlot: slot,
        onConfirm: (title, start, end) async {
          final updatedSlot = TimeSlot(
            start: start,
            end: end,
            type: slot.type,
            availability: slot.availability,
          );
          final groupProvider = context.read<GroupProvider>();

          final success = await scheduler.createMeeting(
            title: title,
            slot: updatedSlot,
            chatId: groupProvider.chatId,
          );

          if (success && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Встреча успешно забронирована!'),
                backgroundColor: Color(0xFF2ECC71),
                behavior: SnackBarBehavior.floating,
              ),
            );
            // Trigger finalization to update Telegram
            await scheduler.finalizeMeeting(
              chatId: groupProvider.chatId!,
              timeStr: "${DateFormat('HH:mm').format(start)} - ${DateFormat('HH:mm').format(end)} (${DateFormat('d MMMM').format(start)})",
            );
          }
        },
      ),
    );
  }

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }
}

// ---------- Booking Form Sheet Widget (Google Style) ----------

class BookingFormSheet extends StatefulWidget {
  final TimeSlot initialSlot;
  final Future<void> Function(String title, DateTime start, DateTime end) onConfirm;

  const BookingFormSheet({
    super.key,
    required this.initialSlot,
    required this.onConfirm,
  });

  @override
  State<BookingFormSheet> createState() => _BookingFormSheetState();
}

class _BookingFormSheetState extends State<BookingFormSheet>
    with SingleTickerProviderStateMixin {

  final _titleController = TextEditingController();
  final _titleFocus = FocusNode();
  late DateTime _startTime;
  late DateTime _endTime;
  bool _isLoading = false;

  late final AnimationController _animCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  bool get _canSubmit =>
      _titleController.text.trim().isNotEmpty && !_isLoading;

  @override
  void initState() {
    super.initState();
    _startTime = widget.initialSlot.start.toLocal();
    _endTime   = widget.initialSlot.end.toLocal();

    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);

    _animCtrl.forward();
    _titleController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocus.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _startTime : _endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF4A90E2),
            surface: Color(0xFF252525),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startTime = DateTime(
          _startTime.year, _startTime.month, _startTime.day,
          picked.hour, picked.minute,
        );
        if (!_endTime.isAfter(_startTime)) {
          _endTime = _startTime.add(const Duration(minutes: 30));
        }
      } else {
        final candidate = DateTime(
          _startTime.year, _startTime.month, _startTime.day,
          picked.hour, picked.minute,
        );
        if (candidate.isAfter(_startTime)) {
          _endTime = candidate;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Время окончания должно быть позже начала'),
              backgroundColor: Color(0xFFE74C3C),
            ),
          );
        }
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF4A90E2),
            surface: Color(0xFF252525),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    setState(() {
      final diff = _endTime.difference(_startTime);
      _startTime = DateTime(
        picked.year, picked.month, picked.day,
        _startTime.hour, _startTime.minute,
      );
      _endTime = _startTime.add(diff);
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _isLoading = true);
    await widget.onConfirm(
      _titleController.text.trim(),
      _startTime,
      _endTime,
    );
    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 40,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHandle(),
                _buildHeader(),
                const Divider(color: Color(0xFF2A2A2A), height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        _buildTitleField(),
                        const SizedBox(height: 4),
                        _buildDateRow(),
                        const SizedBox(height: 4),
                        _buildTimeRow(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Container(
      width: 36, height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFF404040),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 8, 12),
    child: Row(
      children: [
        const Icon(Icons.event_rounded, color: Color(0xFF4A90E2), size: 22),
        const SizedBox(width: 10),
        const Text(
          'Новая встреча',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF707070), size: 22),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );

  Widget _buildTitleField() => TextField(
    controller: _titleController,
    focusNode: _titleFocus,
    autofocus: true,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 22,
      fontWeight: FontWeight.w500,
    ),
    decoration: const InputDecoration(
      hintText: 'Название встречи',
      hintStyle: TextStyle(
        color: Color(0xFF505050),
        fontSize: 22,
        fontWeight: FontWeight.w400,
      ),
      border: InputBorder.none,
      contentPadding: EdgeInsets.symmetric(vertical: 8),
    ),
    textCapitalization: TextCapitalization.sentences,
    onSubmitted: (_) => FocusScope.of(context).unfocus(),
  );

  Widget _buildDateRow() => _InfoRow(
    icon: Icons.calendar_today_rounded,
    label: DateFormat('EEEE, d MMMM yyyy', 'ru').format(_startTime),
    onTap: _pickDate,
  );

  Widget _buildTimeRow() => Row(
    children: [
      const SizedBox(width: 4),
      const Icon(Icons.schedule_rounded, color: Color(0xFF606060), size: 20),
      const SizedBox(width: 12),
      Expanded(
        child: Row(
          children: [
            _TimeChip(
              time: _startTime,
              onTap: () => _pickTime(isStart: true),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('—', style: TextStyle(color: Color(0xFF606060))),
            ),
            _TimeChip(
              time: _endTime,
              onTap: () => _pickTime(isStart: false),
            ),
            const SizedBox(width: 8),
            _DurationBadge(start: _startTime, end: _endTime),
          ],
        ),
      ),
    ],
  );

  Widget _buildFooter() => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
    ),
    child: SizedBox(
      width: double.infinity,
      height: 52,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: ElevatedButton(
          onPressed: _canSubmit ? _submit : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _canSubmit
                ? const Color(0xFF4A90E2)
                : const Color(0xFF2A2A2A),
            foregroundColor: _canSubmit
                ? Colors.white
                : const Color(0xFF505050),
            elevation: _canSubmit ? 4 : 0,
            shadowColor: const Color(0xFF4A90E2).withOpacity(0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5,
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline_rounded, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Забронировать',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _InfoRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF606060), size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD0D0D0),
              fontSize: 15,
            ),
          ),
          const Spacer(),
          const Icon(Icons.chevron_right_rounded,
              color: Color(0xFF404040), size: 18),
        ],
      ),
    ),
  );
}

class _TimeChip extends StatelessWidget {
  final DateTime time;
  final VoidCallback onTap;

  const _TimeChip({required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Text(
        DateFormat('HH:mm').format(time),
        style: const TextStyle(
          color: Color(0xFF4A90E2),
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _DurationBadge extends StatelessWidget {
  final DateTime start;
  final DateTime end;

  const _DurationBadge({required this.start, required this.end});

  String get _label {
    final mins = end.difference(start).inMinutes;
    if (mins < 0) return '0 мин';
    if (mins < 60) return '$mins мин';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '$h ч' : '$h ч $m м';
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFF4A90E2).withOpacity(0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      _label,
      style: const TextStyle(
        color: Color(0xFF4A90E2),
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
