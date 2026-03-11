import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_scheduler_frontend/providers/solo_provider.dart';
import 'package:smart_scheduler_frontend/providers/meeting_provider.dart';
import 'package:smart_scheduler_frontend/providers/language_provider.dart';
import 'package:smart_scheduler_frontend/screens/scheduler/widgets/heatmap_grid.dart';

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
                // For solo view, clicking a slot could show details or allow "blocking" time
                _showSlotDetails(context, slot);
              },
              myMeetings: meetingProvider.meetings,
            ),
          ),
        ),
      ],
    );
  }

  void _showSlotDetails(BuildContext context, dynamic slot) {
    // Placeholder for personal slot management
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Здесь будет управление твоим личным временем!")),
    );
  }
}
