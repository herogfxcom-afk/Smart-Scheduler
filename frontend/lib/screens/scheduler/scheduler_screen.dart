import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../providers/scheduler_provider.dart';
import '../../providers/group_provider.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scheduler = context.read<SchedulerProvider>();
      final groupProvider = context.read<GroupProvider>();
      
      // Load group participants and REFRESH them to trigger ghost cleanup
      if (groupProvider.chatId != null) {
        groupProvider.syncWithGroup().then((_) {
          scheduler.fetchCommonSlots(groupProvider.participants.map((p) => p.telegramId).toList());
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheduler = context.watch<SchedulerProvider>();
    final groupProvider = context.watch<GroupProvider>();
    
    // Group slots by day
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
        title: const Text("Team Availability"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        actions: [
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
                    // Re-fetch slots or filter locally
                    scheduler.findBestTime();
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
                      onSlotSelected: (slot) => _showConfirmation(context, scheduler, slot),
                    )
                  : _buildListSlots(slotsForDay, scheduler),
            ),
          ),
        ],
      ),
    );
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
    final start = "${slot.start.hour}:${slot.start.minute.toString().padLeft(2, '0')}";
    final end = "${slot.end.hour}:${slot.end.minute.toString().padLeft(2, '0')}";
    
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
        onTap: () => _showConfirmation(context, scheduler, slot),
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

  void _showConfirmation(BuildContext context, SchedulerProvider scheduler, TimeSlot slot) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Book this slot?",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                "Date: ${_selectedDay.day}/${_selectedDay.month}\nTime: ${slot.start.hour}:${slot.start.minute.toString().padLeft(2, '0')} - ${slot.end.hour}:${slot.end.minute.toString().padLeft(2, '0')}",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: scheduler.isLoading 
                  ? null 
                  : () async {
                      final groupProvider = context.read<GroupProvider>();
                      final List<String> emails = groupProvider.participants
                          .where((p) => p.isSynced && p.email != null)
                          .map((p) => p.email!)
                          .toList();

                      final success = await scheduler.createMeeting(
                        title: "Group Sync Meeting", 
                        slot: slot,
                        attendeeEmails: emails,
                        chatId: groupProvider.chatId,
                      );

                      if (success && groupProvider.chatId != null) {
                        // Call finalize to update Telegram message
                        final timeStr = "${DateFormat('EEEE, d MMMM, HH:mm').format(slot.start)}";
                        await scheduler.finalizeMeeting(
                          chatId: groupProvider.chatId!,
                          timeStr: timeStr,
                        );
                      }

                      if (mounted) {
                        Navigator.of(context).pop(); // Close bottom sheet
                        // Close the Mini App
                        context.read<TelegramService>().close();
                      }
                    },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: scheduler.isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Confirm"),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }
}
