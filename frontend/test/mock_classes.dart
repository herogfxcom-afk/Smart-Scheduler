import 'package:mocktail/mocktail.dart';
import 'package:smart_scheduler_frontend/core/telegram/telegram_service.dart';
import 'package:smart_scheduler_frontend/providers/availability_provider.dart';
import 'package:smart_scheduler_frontend/providers/solo_provider.dart';
import 'package:smart_scheduler_frontend/providers/auth_provider.dart';
import 'package:smart_scheduler_frontend/providers/meeting_provider.dart';
import 'package:smart_scheduler_frontend/models/availability.dart';

class MockTelegramService extends Mock implements TelegramService {}
class MockAvailabilityProvider extends Mock implements AvailabilityProvider {}
class MockSoloProvider extends Mock implements SoloProvider {}
class MockAuthProvider extends Mock implements AuthProvider {}
class MockMeetingProvider extends Mock implements MeetingProvider {}

List<Availability> mockMoscowAvailability() {
  return List.generate(7, (i) => Availability(
    dayOfWeek: i,
    startTime: '09:00',
    endTime: '18:00',
    isEnabled: i < 5, // Mon-Fri
  ));
}

List<Availability> mockFractionalAvailability() {
  return List.generate(7, (i) => Availability(
    dayOfWeek: i,
    startTime: '09:30',
    endTime: '17:45',
    isEnabled: i < 5,
  ));
}
