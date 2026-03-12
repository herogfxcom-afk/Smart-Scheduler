import 'package:flutter/foundation.dart';
import '../models/availability.dart';
import '../core/api/api_service.dart';

class AvailabilityProvider extends ChangeNotifier {
  final ApiService _apiService;
  List<Availability> _availability = [];
  bool _isLoading = false;
  String? _error;
  DateTime lastUpdated = DateTime.now();

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
      lastUpdated = DateTime.now();
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
      _error = null;
      notifyListeners();

      final data = _availability.map((a) => a.toJson()).toList();
      await _apiService.updateAvailability(data);
      lastUpdated = DateTime.now();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updateDay(int dayIndex, {String? start, String? end, bool? enabled}) {
    final index = _availability.indexWhere((a) => a.dayOfWeek == dayIndex);
    if (index != -1) {
      final old = _availability[index];
      _availability[index] = Availability(
        dayOfWeek: old.dayOfWeek,
        startTime: start ?? old.startTime,
        endTime: end ?? old.endTime,
        isEnabled: enabled ?? old.isEnabled,
      );
      lastUpdated = DateTime.now();
      notifyListeners();
    }
  }
}
