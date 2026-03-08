import 'package:flutter/material.dart';
import '../core/api/api_service.dart';
import '../core/database/database_service.dart';
import '../models/busy_slot.dart';

class SyncProvider extends ChangeNotifier {
  final ApiService _apiService;
  final DatabaseService _databaseService;

  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  int _syncedCount = 0;
  String? _error;

  SyncProvider(this._apiService, this._databaseService);

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
      
      // 2. Fetch busy slots from backend
      final response = await _apiService.get('/calendar/busy-slots');
      final List<dynamic> slotsData = response.data;
      
      final slots = slotsData.map((s) => BusySlot(
        startTime: DateTime.parse(s['start']),
        endTime: DateTime.parse(s['end']),
      )).toList();
      
      // 3. Save to Isar
      await _databaseService.saveBusySlots(slots);
      // 4. Update UI
      _lastSyncTime = DateTime.now();
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

  Future<List<BusySlot>> getLocalSlots() async {
    return await _databaseService.getBusySlots();
  }
}
