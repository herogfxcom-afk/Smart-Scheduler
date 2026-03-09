import 'package:flutter/material.dart';
import '../core/api/api_service.dart';
import '../models/availability.dart';

class AvailabilityProvider with ChangeNotifier {
  final ApiService _apiService;
  List<Availability> _availability = [];
  bool _isLoading = false;
  String? _error;

  AvailabilityProvider(this._apiService);

  List<Availability> get availability => _availability;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchAvailability() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final data = await _apiService.getAvailability();
      _availability = data.map((a) => Availability.fromJson(a)).toList();
      
      // Sort by day of week
      _availability.sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveAvailability() async {
    try {
      _isLoading = true;
      notifyListeners();

      final data = _availability.map((a) => a.toJson()).toList();
      await _apiService.updateAvailability(data);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updateDay(int dayOfWeek, {String? start, String? end, bool? enabled}) {
    final index = _availability.indexWhere((a) => a.dayOfWeek == dayOfWeek);
    if (index != -1) {
      final old = _availability[index];
      _availability[index] = Availability(
        dayOfWeek: dayOfWeek,
        startTime: start ?? old.startTime,
        endTime: end ?? old.endTime,
        isEnabled: enabled ?? old.isEnabled,
      );
      notifyListeners();
    }
  }
}
