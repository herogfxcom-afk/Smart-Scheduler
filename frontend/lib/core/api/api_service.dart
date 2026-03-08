import 'package:dio/dio.dart';
import '../telegram/telegram_service.dart';

class ApiService {
  final Dio _dio;
  final TelegramService _telegramService;

  ApiService(this._telegramService)
      : _dio = Dio(BaseOptions(
          baseUrl: const String.fromEnvironment('API_URL', defaultValue: 'https://web-production-ed04f.up.railway.app'),
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
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
}
