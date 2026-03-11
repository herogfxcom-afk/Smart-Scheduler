import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_scheduler_frontend/providers/solo_provider.dart';
import 'package:smart_scheduler_frontend/providers/meeting_provider.dart';
import 'package:smart_scheduler_frontend/providers/language_provider.dart';
import 'package:smart_scheduler_frontend/screens/scheduler/widgets/heatmap_grid.dart';
import 'package:smart_scheduler_frontend/models/time_slot.dart';

class SoloDashboard extends StatefulWidget {
  const SoloDashboard({super.key});

  @override
  State<SoloDashboard> createState() => _SoloDashboardState();
}

class _SoloDashboardState extends State<SoloDashboard> {
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SoloProvider>().fetchSoloSlots();
    });
  }

  @override
  Widget build(BuildContext context) {
    final soloProvider = context.watch<SoloProvider>();
    final meetingProvider = context.watch<MeetingProvider>();
    final lang = context.watch<LanguageProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              lang.translate('my_smart_schedule'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (soloProvider.isLoading)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 350,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: HeatmapGrid(
              slots: soloProvider.slots,
              selectedDay: _selectedDay,
              onSlotSelected: (slot) {
                if (slot is TimeSlot) {
                  _showSlotDetails(context, slot);
                }
              },
              myMeetings: meetingProvider.meetings,
            ),
          ),
        ),
      ],
    );
  }

  void _showSlotDetails(BuildContext context, TimeSlot slot) {
    final soloProvider = context.read<SoloProvider>();
    final isBusy = slot.type == 'my_busy' || slot.type == 'busy';
    
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
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
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
                Icon(
                  isBusy ? Icons.event_busy : Icons.event_available,
                  color: isBusy ? Colors.orangeAccent : Colors.greenAccent,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  isBusy ? "Это время занято" : "Это время свободно",
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "${slot.start.hour}:${slot.start.minute.toString().padLeft(2, '0')} - ${slot.end.hour}:${slot.end.minute.toString().padLeft(2, '0')}",
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : () async {
                      setState(() => isProcessing = true);
                      if (isBusy) {
                        await soloProvider.freeSlot(slot.start, slot.end);
                      } else {
                        await soloProvider.reserveSlot(slot.start, slot.end);
                      }
                      if (context.mounted) Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isBusy ? Colors.red.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                      foregroundColor: isBusy ? Colors.redAccent : Colors.greenAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      side: BorderSide(color: isBusy ? Colors.redAccent : Colors.greenAccent, width: 1),
                    ),
                    child: isProcessing 
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(isBusy ? "Освободить время" : "Занять это время", 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Назад", style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
