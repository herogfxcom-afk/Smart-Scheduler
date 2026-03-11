import 'package:dio/dio.dart';
import '../telegram/telegram_service.dart';

class ApiService {
  final Dio _dio;
  final TelegramService _telegramService;

  ApiService(this._telegramService)
      : _dio = Dio(BaseOptions(
          baseUrl: const String.fromEnvironment('API_URL', defaultValue: ''),
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        )) {
    if (_dio.options.baseUrl.isEmpty) {
      _dio.options.baseUrl = 'https://smart-scheduler-production-2006.up.railway.app'; // Default to production
    }

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final initData = _telegramService.initData;
        if (initData.isNotEmpty) {
          options.headers['init-data'] = initData;
        }
        return handler.next(options);
      },
      onError: (e, handler) {
        print("API Error: ${e.message}");
        return handler.next(e);
      },
    ));
  }

  Future<Response> get(String path) async {
    return await _dio.get(path);
  }

  Future<Response> post(String path, dynamic data) async {
    return await _dio.post(path, data: data);
  }

  Future<Response> patch(String path, dynamic data) async {
    return await _dio.patch(path, data: data);
  }

  Future<Response> delete(String path, {Map<String, dynamic>? queryParameters}) async {
    return await _dio.delete(path, queryParameters: queryParameters);
  }

  Future<String> getGoogleAuthUrl() async {
    try {
      final response = await _dio.get('/auth/google/url');
      return response.data['url'] as String;
    } catch (e) {
      throw Exception('Failed to get Google Auth URL: $e');
    }
  }

  Future<String> getOutlookAuthUrl() async {
    try {
      final response = await _dio.get('/auth/outlook/url');
      return response.data['url'] as String;
    } catch (e) {
      throw Exception('Failed to get Outlook Auth URL: $e');
    }
  }

  Future<Map<String, dynamic>> getMe() async {
    try {
      final response = await _dio.get('/auth/me');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to fetch user profile: $e');
    }
  }

  // Meeting Management
  Future<List<dynamic>> getMyMeetings() async {
    final response = await _dio.get('/api/meetings/my');
    return response.data as List<dynamic>;
  }

  Future<void> deleteMeeting(int id) async {
    await _dio.delete('/api/meetings/$id');
  }

  Future<void> updateMeeting(int id, Map<String, dynamic> data) async {
    await _dio.patch('/api/meetings/$id', data: data);
  }

  Future<void> respondToInvite(int inviteId, String status) async {
    await _dio.post('/api/invites/$inviteId/respond', data: {'status': status});
  }

  // Availability
  Future<List<dynamic>> getAvailability() async {
    final response = await _dio.get('/api/availability');
    return response.data as List<dynamic>;
  }

  Future<void> updateAvailability(List<Map<String, dynamic>> data) async {
    await _dio.post('/api/availability', data: data);
  }

  // Solo Scheduler
  Future<List<dynamic>> getSoloSlots(double tzOffset) async {
    final response = await _dio.get('/api/scheduler/solo', queryParameters: {
      'tz_offset': tzOffset,
    });
    return response.data as List<dynamic>;
  }

  Future<void> addBusySlot(DateTime start, DateTime end) async {
    await _dio.post('/api/busy-slots', data: {
      'start': start.toUtc().toIsoformat(),
      'end': end.toUtc().toIsoformat(),
    });
  }

  Future<void> deleteBusySlot(DateTime start, DateTime end) async {
    await _dio.delete('/api/busy-slots', queryParameters: {
      'start': start.toUtc().toIsoformat(),
      'end': end.toUtc().toIsoformat(),
    });
  }
}

extension DateTimeExtension on DateTime {
  String toIsoformat() => toIso8601String().split('.')[0] + 'Z';
}
