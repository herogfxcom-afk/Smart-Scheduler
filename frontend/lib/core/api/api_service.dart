import 'package:dio/dio.dart';
import '../telegram/telegram_service.dart';

class ApiService {
  final Dio _dio;
  final TelegramService _telegramService;

  ApiService(this._telegramService)
      : _dio = Dio(BaseOptions(
          baseUrl: const String.fromEnvironment('API_URL', defaultValue: 'https://smart-scheduler-production-2006.up.railway.app'),
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        )) {
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

  Future<String> getGoogleAuthUrl() async {
    try {
      final response = await _dio.get('/auth/google/url');
      return response.data['url'] as String;
    } catch (e) {
      throw Exception('Failed to get Google Auth URL: $e');
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

  // Invites
  Future<List<dynamic>> getPendingInvites() async {
    final response = await _dio.get('/api/invites');
    return response.data as List<dynamic>;
  }

  Future<void> respondToInvite(int inviteId, String action) async {
    await _dio.post('/api/invites/$inviteId/respond', data: {'action': action});
  }

  // Availability
  Future<List<dynamic>> getAvailability() async {
    final response = await _dio.get('/api/availability');
    return response.data as List<dynamic>;
  }

  Future<void> updateAvailability(List<Map<String, dynamic>> data) async {
    await _dio.post('/api/availability', data: data);
  }
}
