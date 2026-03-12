import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:smart_scheduler_frontend/core/api/api_service.dart';
import 'package:smart_scheduler_frontend/models/time_slot.dart';

import 'package:smart_scheduler_frontend/utils/timezone_utils.dart';

class SoloProvider with ChangeNotifier {
  final ApiService _apiService;
  List<TimeSlot> _slots = [];
  bool _isLoading = false;
  String? _error;

  SoloProvider(this._apiService);

  List<TimeSlot> get slots => _slots;
  bool get isLoading => _isLoading;
  String? get errorText => _error;

  String _parseError(dynamic e) {
    if (e is DioException) {
      if (e.response?.data != null && e.response?.data is Map) {
         return e.response!.data['detail']?.toString() ?? e.message ?? "Ошибка сервера";
      }
      return e.message ?? "Сетевая ошибка";
    }
    return e.toString();
  }

  Future<void> fetchSoloSlots() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final tzOffset = getUserTzOffset();
      final data = await _apiService.getSoloSlots(tzOffset);
      _slots = data.map((s) => TimeSlot.fromJson(s)).toList();
    } catch (e) {
      _error = _parseError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> reserveSlot(DateTime start, DateTime end) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();
      await _apiService.addBusySlot(start, end);
      await fetchSoloSlots(); 
    } catch (e) {
      _error = _parseError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> freeSlot(DateTime start, DateTime end) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();
      await _apiService.deleteBusySlot(start, end);
      await fetchSoloSlots(); 
    } catch (e) {
      _error = _parseError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
