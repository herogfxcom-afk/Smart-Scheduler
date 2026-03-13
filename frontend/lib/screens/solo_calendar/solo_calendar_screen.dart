import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/solo_provider.dart';
import '../../providers/meeting_provider.dart';
import '../scheduler/widgets/heatmap_grid.dart';
import '../../utils/calendar_processor.dart';
import '../../utils/timezone_utils.dart';
import '../../providers/availability_provider.dart';

class SoloCalendarScreen extends StatelessWidget {
  const SoloCalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final soloProvider = context.watch<SoloProvider>();
    final meetingProvider = context.watch<MeetingProvider>();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Мой календарь", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => soloProvider.fetchSoloSlots(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildDaySelector(context, soloProvider),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF121212),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: soloProvider.isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.blue))
                  : HeatmapGrid(
                      slots: soloProvider.slots,
                      selectedDay: userNow(), // Or track in provider
                      availability: context.watch<AvailabilityProvider>().availability,
                      onSlotSelected: (slot) {
                        // Handle solo slot tap
                      },
                      calendarType: CalendarType.solo,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaySelector(BuildContext context, SoloProvider provider) {
    final now = userNow();
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 14,
        itemBuilder: (context, index) {
          final day = now.add(Duration(days: index));
          // For now using today as reference, in a real app would use a state
          final isSelected = day.day == now.day; 

          return Container(
            width: 55,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(15),
              border: isSelected ? null : Border.all(color: Colors.white.withOpacity(0.1)),
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
          );
        },
      ),
    );
  }
}
