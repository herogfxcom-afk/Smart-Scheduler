import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_scheduler_frontend/screens/scheduler/widgets/heatmap_grid.dart';
import 'package:smart_scheduler_frontend/models/time_slot.dart';
import 'package:smart_scheduler_frontend/models/meeting.dart';
import 'package:smart_scheduler_frontend/providers/availability_provider.dart';
import 'package:smart_scheduler_frontend/providers/auth_provider.dart';
import 'package:smart_scheduler_frontend/providers/meeting_provider.dart';
import 'package:smart_scheduler_frontend/providers/solo_provider.dart';
import 'package:smart_scheduler_frontend/core/telegram/telegram_service.dart';
import 'package:smart_scheduler_frontend/utils/calendar_processor.dart';
import 'package:smart_scheduler_frontend/providers/working_hours_notifier.dart';
import 'package:smart_scheduler_frontend/providers/language_provider.dart';
import '../mock_classes.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await loadAppFonts();
    tz.initializeTimeZones();
  });

  group('HeatmapGrid Golden Tests', () {
    late MockTelegramService mockTelegram;
    late MockAvailabilityProvider mockAvailability;
    late MockSoloProvider mockSolo;
    late MockAuthProvider mockAuth;
    late MockMeetingProvider mockMeeting;
    late WorkingHoursNotifier workingHoursNotifier;
    late LanguageProvider languageProvider;

    setUp(() {
      mockTelegram = MockTelegramService();
      mockAvailability = MockAvailabilityProvider();
      mockSolo = MockSoloProvider();
      mockAuth = MockAuthProvider();
      mockMeeting = MockMeetingProvider();
      workingHoursNotifier = WorkingHoursNotifier();
      languageProvider = LanguageProvider();

      when(() => mockTelegram.getUserId()).thenReturn('user_123');
      when(() => mockAvailability.availability).thenReturn(mockMoscowAvailability());
      when(() => mockAvailability.lastUpdated).thenReturn(DateTime(2025, 1, 1));
      
      // Basic mocks for SoloProvider dependencies
      when(() => mockSolo.fetchSoloSlots(force: any(named: 'force'))).thenAnswer((_) async {});
      when(() => mockAuth.user).thenReturn(null);
      when(() => mockMeeting.meetings).thenReturn([]);
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
              ChangeNotifierProvider<SoloProvider>.value(value: mockSolo),
              ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
              ChangeNotifierProvider<MeetingProvider>.value(value: mockMeeting),
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
              ChangeNotifierProvider<SoloProvider>.value(value: mockSolo),
              ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
              ChangeNotifierProvider<MeetingProvider>.value(value: mockMeeting),
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
              ChangeNotifierProvider<SoloProvider>.value(value: mockSolo),
              ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
              ChangeNotifierProvider<MeetingProvider>.value(value: mockMeeting),
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
              ChangeNotifierProvider<SoloProvider>.value(value: mockSolo),
              ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
              ChangeNotifierProvider<MeetingProvider>.value(value: mockMeeting),
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
              ChangeNotifierProvider<SoloProvider>.value(value: mockSolo),
              ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
              ChangeNotifierProvider<MeetingProvider>.value(value: mockMeeting),
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

    testGoldens('External Busy Highlighting - Blue Blocks', (tester) async {
      tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
      final baseDate = DateTime(2026, 3, 13, 0, 0, 0);
      
      final builder = DeviceBuilder()
        ..overrideDevicesForAllScenarios(devices: [
          const Device(name: 'web_view', size: Size(400, 800)),
        ])
        ..addScenario(
          name: 'external_busy_blue_blocks',
          widget: MultiProvider(
            providers: [
              Provider<TelegramService>.value(value: mockTelegram),
              ChangeNotifierProvider<AvailabilityProvider>.value(value: mockAvailability),
              ChangeNotifierProvider<WorkingHoursNotifier>.value(value: workingHoursNotifier),
              ChangeNotifierProvider<SoloProvider>.value(value: mockSolo),
              ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
              ChangeNotifierProvider<MeetingProvider>.value(value: mockMeeting),
            ],
            child: Material(
              child: HeatmapGrid(
                slots: [
                  // 1. External busy slot with summary (Blue)
                  TimeSlot(
                    start: DateTime.parse('2026-03-13T08:00:00Z'),
                    end: DateTime.parse('2026-03-13T09:30:00Z'),
                    type: 'my_busy',
                    summary: 'External Lunch',
                    availability: 0.0,
                  ),
                  // 2. External busy slot WITHOUT summary (Grey "Занято")
                  TimeSlot(
                    start: DateTime.parse('2026-03-13T10:00:00Z'),
                    end: DateTime.parse('2026-03-13T11:00:00Z'),
                    type: 'my_busy',
                    availability: 0.0,
                  ),
                ],
                myMeetings: [
                  // 3. App-created meeting (Purple)
                  Meeting(
                    id: 1,
                    title: 'App Strategy',
                    start: DateTime.parse('2026-03-13T12:00:00Z'),
                    end: DateTime.parse('2026-03-13T13:30:00Z'),
                    status: 'accepted',
                    isCreator: true,
                    provider: 'app',
                  ),
                ],
                selectedDay: baseDate,
                onSlotSelected: (_) {},
                availability: mockMoscowAvailability(),
                myUserId: 'user_123',
                calendarType: CalendarType.solo,
              ),
            ),
          ),
        );

      await tester.pumpDeviceBuilder(builder);
      await screenMatchesGolden(tester, 'heatmap_external_busy');
    });

    testGoldens('Cancelled Meeting - Red Line UI', (tester) async {
      tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
      final baseDate = DateTime(2026, 3, 13, 0, 0, 0);
      
      final builder = DeviceBuilder()
        ..overrideDevicesForAllScenarios(devices: [
          const Device(name: 'web_view', size: Size(400, 800)),
        ])
        ..addScenario(
          name: 'cancelled_meeting_view',
          widget: MultiProvider(
            providers: [
              Provider<TelegramService>.value(value: mockTelegram),
              ChangeNotifierProvider<AvailabilityProvider>.value(value: mockAvailability),
              ChangeNotifierProvider<WorkingHoursNotifier>.value(value: workingHoursNotifier),
              ChangeNotifierProvider<SoloProvider>.value(value: mockSolo),
              ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
              ChangeNotifierProvider<MeetingProvider>.value(value: mockMeeting),
            ],
            child: Material(
              child: HeatmapGrid(
                slots: [],
                myMeetings: [
                  Meeting(
                    id: 99,
                    title: 'Cancelled Brainstorm',
                    start: DateTime.parse('2026-03-13T14:00:00Z'),
                    end: DateTime.parse('2026-03-13T15:00:00Z'),
                    status: 'cancelled',
                    isCreator: false,
                    provider: 'app',
                  ),
                ],
                selectedDay: baseDate,
                onSlotSelected: (_) {},
                availability: mockMoscowAvailability(),
                myUserId: 'user_123',
                calendarType: CalendarType.solo,
              ),
            ),
          ),
        );

      await tester.pumpDeviceBuilder(builder);
      await screenMatchesGolden(tester, 'heatmap_cancelled_meeting');
    });
    testGoldens('DST Transition - London (March 29, 2026)', (tester) async {
      // London jumps from 01:00 to 02:00
      tz.setLocalLocation(tz.getLocation('Europe/London'));
      final baseDate = DateTime(2026, 3, 29, 0, 0, 0); // DST Sunday
      
      final slots = [
        // Match at 00:00 (GMT)
        TimeSlot(
          start: DateTime.parse('2026-03-29T00:00:00Z'),
          end: DateTime.parse('2026-03-29T01:00:00Z'),
          type: 'match',
          availability: 1.0,
        ),
        // Match at 02:00 (BST) - note that 01:00-02:00 local doesn't exist
        TimeSlot(
          start: DateTime.parse('2026-03-29T01:00:00Z'),
          end: DateTime.parse('2026-03-29T02:00:00Z'),
          type: 'match',
          availability: 1.0,
        ),
      ];

      final builder = DeviceBuilder()
        ..overrideDevicesForAllScenarios(devices: [
          const Device(name: 'web_view', size: Size(400, 800)),
        ])
        ..addScenario(
          name: 'london_dst_transition',
          widget: MultiProvider(
            providers: [
              Provider<TelegramService>.value(value: mockTelegram),
              ChangeNotifierProvider<AvailabilityProvider>.value(value: mockAvailability),
              ChangeNotifierProvider<WorkingHoursNotifier>.value(value: workingHoursNotifier),
              ChangeNotifierProvider<SoloProvider>.value(value: mockSolo),
              ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
              ChangeNotifierProvider<MeetingProvider>.value(value: mockMeeting),
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
      await screenMatchesGolden(tester, 'heatmap_dst_london');
    });

    testGoldens('Localization & Accessibility - Russian Overflows', (tester) async {
      tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
      final baseDate = DateTime(2026, 3, 13, 0, 0, 0);
      
      // Force Russian
      await languageProvider.setLocale('ru');

      final builder = DeviceBuilder()
        ..overrideDevicesForAllScenarios(devices: [
          const Device(name: 'russian_ui_overflow_check', size: Size(375, 812)), // iPhone 13-ish
        ])
        ..addScenario(
          name: 'russian_localization',
          widget: MultiProvider(
            providers: [
              Provider<TelegramService>.value(value: mockTelegram),
              ChangeNotifierProvider<AvailabilityProvider>.value(value: mockAvailability),
              ChangeNotifierProvider<WorkingHoursNotifier>.value(value: workingHoursNotifier),
              ChangeNotifierProvider<LanguageProvider>.value(value: languageProvider),
              ChangeNotifierProvider<SoloProvider>.value(value: mockSolo),
              ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
              ChangeNotifierProvider<MeetingProvider>.value(value: mockMeeting),
            ],
            child: Material(
              child: HeatmapGrid(
                slots: mockMoscowSlots(),
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
      await screenMatchesGolden(tester, 'heatmap_localization_ru');
    });

    testGoldens('Responsive Layout - Small Devices', (tester) async {
      tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
      final baseDate = DateTime(2026, 3, 13, 0, 0, 0);

      final builder = DeviceBuilder()
        ..overrideDevicesForAllScenarios(devices: [
          const Device(name: 'small_screen_se', size: Size(320, 568)), // iPhone SE
        ])
        ..addScenario(
          name: 'narrow_screen_grid',
          widget: MultiProvider(
            providers: [
              Provider<TelegramService>.value(value: mockTelegram),
              ChangeNotifierProvider<AvailabilityProvider>.value(value: mockAvailability),
              ChangeNotifierProvider<WorkingHoursNotifier>.value(value: workingHoursNotifier),
              ChangeNotifierProvider<LanguageProvider>(create: (_) => LanguageProvider()),
              ChangeNotifierProvider<SoloProvider>.value(value: mockSolo),
              ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
              ChangeNotifierProvider<MeetingProvider>.value(value: mockMeeting),
            ],
            child: Material(
              child: HeatmapGrid(
                slots: mockMoscowSlots(),
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
      await screenMatchesGolden(tester, 'heatmap_responsive_small');
    });
  });
}

List<TimeSlot> mockMoscowSlots() {
  return [
    TimeSlot(
      start: DateTime.parse('2026-03-13T13:00:00Z'),
      end: DateTime.parse('2026-03-13T15:00:00Z'),
      type: 'match',
      availability: 1.0,
    ),
  ];
}
