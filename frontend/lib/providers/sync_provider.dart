import 'package:flutter/material.dart';
import '../utils/timezone_utils.dart';
import '../core/api/api_service.dart';

import '../models/busy_slot.dart';

class SyncProvider extends ChangeNotifier {
  final ApiService _apiService;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  int _syncedCount = 0;
  String? _error;

  SyncProvider(this._apiService);

  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get syncedCount => _syncedCount;
  String? get error => _error;

  Future<void> sync() async {
    _isSyncing = true;
    _error = null;
    notifyListeners();

    try {
      // 1. Trigger backend sync
      final syncRes = await _apiService.post('/calendar/sync', {});
      _syncedCount = syncRes.data['synced_count'] ?? 0;
      
      // 4. Update UI
      _lastSyncTime = userNow();
      _isSyncing = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      print("Sync Error: $e");
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
}
