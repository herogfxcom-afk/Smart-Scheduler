import 'package:flutter/material.dart';
import '../core/api/api_service.dart';
import '../models/meeting.dart';

class MeetingProvider with ChangeNotifier {
  final ApiService _apiService;
  List<Meeting> _meetings = [];
  bool _isLoading = false;
  String? _error;

  MeetingProvider(this._apiService);

  List<Meeting> get meetings => _meetings;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchMyMeetings() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final data = await _apiService.getMyMeetings();
      _meetings = data.map((m) => Meeting.fromJson(m)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteMeeting(int id) async {
    try {
      await _apiService.deleteMeeting(id);
      _meetings.removeWhere((m) => m.id == id);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateMeeting(int id, Map<String, dynamic> data) async {
    try {
      await _apiService.updateMeeting(id, data);
      await fetchMyMeetings(); // Refresh
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
}
