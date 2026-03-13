import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/availability_provider.dart';
import '../../providers/working_hours_notifier.dart';
import '../../models/availability.dart';

class AvailabilitySettingsScreen extends StatefulWidget {
  const AvailabilitySettingsScreen({super.key});

  @override
  State<AvailabilitySettingsScreen> createState() => _AvailabilitySettingsScreenState();
}

class _AvailabilitySettingsScreenState extends State<AvailabilitySettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AvailabilityProvider>().fetchAvailability();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AvailabilityProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Рабочие часы'),
        actions: [
          if (!provider.isLoading)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: () async {
                await provider.saveAvailability();
                if (mounted) {
                  context.read<WorkingHoursNotifier>().refresh();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Настройки сохранены')),
                  );
                }
              },
            ),
        ],
      ),
      body: provider.isLoading && provider.availability.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: provider.availability.length,
              itemBuilder: (context, index) {
                final day = provider.availability[index];
                return _AvailabilityDayTile(day: day);
              },
            ),
    );
  }
}

class _AvailabilityDayTile extends StatelessWidget {
  final Availability day;

  const _AvailabilityDayTile({required this.day});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AvailabilityProvider>();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  day.dayName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Switch(
                  value: day.isEnabled,
                  onChanged: (val) {
                    provider.updateDay(day.dayOfWeek, enabled: val);
                  },
                ),
              ],
            ),
            if (day.isEnabled) ...[
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: _TimePicker(
                      label: 'Начало',
                      time: day.startTime,
                      onChanged: (time) {
                        provider.updateDay(day.dayOfWeek, start: time);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _TimePicker(
                      label: 'Конец',
                      time: day.endTime,
                      onChanged: (time) {
                        provider.updateDay(day.dayOfWeek, end: time);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimePicker extends StatelessWidget {
  final String label;
  final String time;
  final Function(String) onChanged;

  const _TimePicker({
    required this.label,
    required this.time,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final parts = time.split(':');
        final current = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        final picked = await showTimePicker(
          context: context,
          initialTime: current,
        );
        if (picked != null) {
          final formatted = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
          onChanged(formatted);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text(time, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
