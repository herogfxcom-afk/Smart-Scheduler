import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:smart_scheduler_frontend/screens/scheduler/widgets/heatmap_grid.dart';
import 'package:smart_scheduler_frontend/models/time_slot.dart';
import 'package:smart_scheduler_frontend/models/meeting.dart';
import 'package:smart_scheduler_frontend/providers/availability_provider.dart';
import 'package:smart_scheduler_frontend/providers/auth_provider.dart';
import 'package:smart_scheduler_frontend/providers/meeting_provider.dart';
import 'package:smart_scheduler_frontend/models/availability.dart';
import 'package:smart_scheduler_frontend/core/telegram/telegram_service.dart';
import 'package:smart_scheduler_frontend/utils/calendar_processor.dart';
import 'package:smart_scheduler_frontend/providers/working_hours_notifier.dart';
import '../mock_classes.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    tz.initializeTimeZones();
  });

  group('HeatmapGrid Golden Tests', () {
    late MockTelegramService mockTelegram;
    late MockAvailabilityProvider mockAvailability;
    late WorkingHoursNotifier workingHoursNotifier;

    setUp(() {
      mockTelegram = MockTelegramService();
      mockAvailability = MockAvailabilityProvider();
      workingHoursNotifier = WorkingHoursNotifier();

      when(() => mockTelegram.getUserId()).thenReturn('user_123');
      when(() => mockAvailability.availability).thenReturn(mockMoscowAvailability());
      when(() => mockAvailability.lastUpdated).thenReturn(DateTime(2025, 1, 1));
    });

    testGoldens('Personal Heatmap - Moscow TZ', (tester) async {
      // Set local timezone to Moscow (+3)
      tz.setLocalLocation(tz.getLocation('Europe/Moscow'));

      final baseDate = DateTime(2026, 3, 13, 0, 0, 0); // Friday
      
      final slots = [
        // match 13:00-15:00Z -> 16:00-18:00 MSK
        TimeSlot(
          start: DateTime.parse('2026-03-13T13:00:00Z'),
          end: DateTime.parse('2026-03-13T15:00:00Z'),
          type: 'match',
          availability: 1.0,
        ),
        // partial 10:00-13:00Z -> 13:00-16:00 MSK
        TimeSlot(
          start: DateTime.parse('2026-03-13T10:00:00Z'),
          end: DateTime.parse('2026-03-13T13:00:00Z'),
          type: 'others_busy',
          availability: 0.5,
          freeCount: 1,
          totalCount: 2,
        ),
      ];

      final builder = DeviceBuilder()
        ..overrideDevicesForAllScenarios(devices: [
          const Device(name: 'web_view', size: Size(400, 800)),
        ])
        ..addScenario(
          name: 'moscow_personal_view',
          widget: MultiProvider(
            providers: [
              Provider<TelegramService>.value(value: mockTelegram),
              ChangeNotifierProvider<AvailabilityProvider>.value(value: mockAvailability),
              ChangeNotifierProvider<WorkingHoursNotifier>.value(value: workingHoursNotifier),
            ],
            child: Material(
              child: HeatmapGrid(
                slots: slots,
                selectedDay: baseDate,
                onSlotSelected: (_) {},
                availability: mockMoscowAvailability(),
                myUserId: 'user_123',
                calendarType: CalendarType.group,
              ),
            ),
          ),
        );

      await tester.pumpDeviceBuilder(builder);
      await screenMatchesGolden(tester, 'heatmap_grid_moscow');
    });

    testGoldens('Multi-TZ Group Heatmap - NY vs Moscow', (tester) async {
      // Viewer is in NY (-4 at this date usually, but let's be explicit if possible)
      // For simplicity of test, we just set the location
      tz.setLocalLocation(tz.getLocation('America/New_York'));

      final baseDate = DateTime(2026, 3, 13, 0, 0, 0);
      
      final slots = [
        // match 13:00-15:00Z -> 09:00-11:00 NY
        TimeSlot(
          start: DateTime.parse('2026-03-13T13:00:00Z'),
          end: DateTime.parse('2026-03-13T15:00:00Z'),
          type: 'match',
          availability: 1.0,
        ),
        // fractional 10:00-13:00Z -> 06:00-09:00 NY
        TimeSlot(
          start: DateTime.parse('2026-03-13T10:00:00Z'),
          end: DateTime.parse('2026-03-13T13:00:00Z'),
          type: 'others_busy',
          availability: 0.5,
          freeCount: 1,
          totalCount: 2,
        ),
      ];

      final builder = DeviceBuilder()
        ..overrideDevicesForAllScenarios(devices: [
          const Device(name: 'web_view', size: Size(400, 800)),
        ])
        ..addScenario(
          name: 'ny_viewer_group_view',
          widget: MultiProvider(
            providers: [
              Provider<TelegramService>.value(value: mockTelegram),
              ChangeNotifierProvider<AvailabilityProvider>.value(value: mockAvailability),
              ChangeNotifierProvider<WorkingHoursNotifier>.value(value: workingHoursNotifier),
            ],
            child: Material(
              child: HeatmapGrid(
                slots: slots,
                selectedDay: baseDate,
                onSlotSelected: (_) {},
                availability: mockMoscowAvailability(),
                myUserId: 'user_123',
                calendarType: CalendarType.group,
              ),
            ),
          ),
        );

      await tester.pumpDeviceBuilder(builder);
      await screenMatchesGolden(tester, 'heatmap_grid_ny');
    });

    testGoldens('Timezone Shift - Grid updates on TZ change', (tester) async {
      tz.setLocalLocation(tz.getLocation('UTC'));
      final baseDate = DateTime(2026, 3, 13, 0, 0, 0);
      final slots = [
        TimeSlot(
          start: DateTime.parse('2026-03-13T10:00:00Z'),
          end: DateTime.parse('2026-03-13T12:00:00Z'),
          type: 'match',
          availability: 1.0,
        ),
      ];

      final builder = DeviceBuilder()
        ..overrideDevicesForAllScenarios(devices: [
          const Device(name: 'web_view', size: Size(400, 800)),
        ])
        ..addScenario(
          name: 'utc_before_shift',
          widget: MultiProvider(
            providers: [
              Provider<TelegramService>.value(value: mockTelegram),
              ChangeNotifierProvider<AvailabilityProvider>.value(value: mockAvailability),
              ChangeNotifierProvider<WorkingHoursNotifier>.value(value: workingHoursNotifier),
            ],
            child: Material(
              child: HeatmapGrid(
                slots: slots,
                selectedDay: baseDate,
                onSlotSelected: (_) {},
                availability: mockMoscowAvailability(),
                myUserId: 'user_123',
                calendarType: CalendarType.group,
              ),
            ),
          ),
        );

      await tester.pumpDeviceBuilder(builder);
      await screenMatchesGolden(tester, 'heatmap_shift_utc');

      // Now shift to Tokyo (+9)
      tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));
      
      // We need to re-build or trigger a shift. 
      // In our code, HeatmapGrid build() uses toUserLocal which uses tz.local.
      // So a pump() should suffice if the state triggers a rebuild.
      
      await tester.pump(); 
      await screenMatchesGolden(tester, 'heatmap_shift_tokyo');
    });

    testGoldens('Fractional Working Hours - 09:30-17:45', (tester) async {
      tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
      final baseDate = DateTime(2026, 3, 13, 0, 0, 0);
      
      when(() => mockAvailability.availability).thenReturn(mockFractionalAvailability());

      final builder = DeviceBuilder()
        ..overrideDevicesForAllScenarios(devices: [
          const Device(name: 'web_view', size: Size(400, 800)),
        ])
        ..addScenario(
          name: 'fractional_hours_view',
          widget: MultiProvider(
            providers: [
              Provider<TelegramService>.value(value: mockTelegram),
              ChangeNotifierProvider<AvailabilityProvider>.value(value: mockAvailability),
              ChangeNotifierProvider<WorkingHoursNotifier>.value(value: workingHoursNotifier),
            ],
            child: Material(
              child: HeatmapGrid(
                slots: [], // Empty slots to focus on background alignment
                selectedDay: baseDate,
                onSlotSelected: (_) {},
                availability: mockFractionalAvailability(),
                myUserId: 'user_123',
                calendarType: CalendarType.group,
              ),
            ),
          ),
        );

      await tester.pumpDeviceBuilder(builder);
      await screenMatchesGolden(tester, 'heatmap_grid_fractional');
    });

    testGoldens('Unified UI Check - No redundant green slots', (tester) async {
      tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
      final baseDate = DateTime(2026, 3, 13, 0, 0, 0);
      
      // Provide Moscow availability but 0 actual slots to ensure background is the focus
      final availability = mockMoscowAvailability();
      workingHoursNotifier.update(availability);

      final builder = DeviceBuilder()
        ..overrideDevicesForAllScenarios(devices: [
          const Device(name: 'web_view', size: Size(400, 800)),
        ])
        ..addScenario(
          name: 'unified_solo_ui',
          widget: MultiProvider(
            providers: [
              Provider<TelegramService>.value(value: mockTelegram),
              ChangeNotifierProvider<AvailabilityProvider>.value(value: mockAvailability),
              ChangeNotifierProvider<WorkingHoursNotifier>.value(value: workingHoursNotifier),
            ],
            child: Material(
              child: HeatmapGrid(
                slots: const [], // No slots, just background
                selectedDay: baseDate,
                onSlotSelected: (_) {},
                availability: availability,
                calendarType: CalendarType.solo,
              ),
            ),
          ),
        );

      await tester.pumpDeviceBuilder(builder);
      await screenMatchesGolden(tester, 'heatmap_unified_solo');
    });
  });
}
