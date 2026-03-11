import 'package:flutter/material.dart';
import 'package:smart_scheduler_frontend/core/api/api_service.dart';
import 'package:smart_scheduler_frontend/models/time_slot.dart';

class SoloProvider with ChangeNotifier {
  final ApiService _apiService;
  List<TimeSlot> _slots = [];
  bool _isLoading = false;
  String? _error;

  SoloProvider(this._apiService);

  List<TimeSlot> get slots => _slots;
  bool get isLoading => _isLoading;
  String? _errorText => _error;

  Future<void> fetchSoloSlots() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final data = await _apiService.getSoloSlots();
      _slots = data.map((s) => TimeSlot.fromJson(s)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
