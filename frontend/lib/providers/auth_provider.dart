import 'package:flutter/material.dart';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import '../models/user.dart';
import '../core/api/api_service.dart';
import '../core/telegram/telegram_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService;
  final TelegramService _telegramService;

  User? _user;
  bool _isLoading = false;
  String? _error;

  AuthProvider(this._apiService, this._telegramService);

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool _isConnected = false;
  bool _isAppleConnected = false;

  bool get isConnected => _isConnected;
  bool get isAppleConnected => _isAppleConnected;

  Future<void> init() async {
    // Only show loading if we don't have a user yet to prevent flickering on background refreshes
    if (_user == null) {
      _isLoading = true;
      notifyListeners();
    }
    
    await refresh();
    
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      final userData = await _apiService.getMe();
      _user = User.fromJson(userData);
      
      // Update individual flags for backward compatibility or simple UI checks
      _isConnected = userData['is_connected'] ?? false;
      _isAppleConnected = userData['is_apple_connected'] ?? false;
      
      _error = null;
      print("Auth State Refreshed: isConnected=$_isConnected, connections=${_user?.connections.length}");
    } catch (e) {
      _error = e.toString();
      print("Auth Refresh Error: $e");
    }
  }

  Future<bool> connectApple(String email, String password) async {
    try {
      await _apiService.post('/auth/apple/connect', {
        'email': email,
        'password': password,
      });
      await init(); // Refresh state
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> connectGoogle() async {
    try {
      final url = await _apiService.getGoogleAuthUrl();
      if (_telegramService.isReady) {
        _telegramService.openLink(url);
      } else {
        globalContext.callMethod('open'.toJS, url.toJS);
      }
    } catch (e) {
      _error = e.toString();
      _telegramService.showPopup(message: "Failed to connect Google: $e");
      notifyListeners();
    }
  }

  void logout() {
    _user = null;
    notifyListeners();
  }
}
