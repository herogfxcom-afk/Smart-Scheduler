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
  
  List<Meeting> get upcomingMeetings {
    final now = DateTime.now();
    return _meetings.where((m) => m.end.isAfter(now)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  List<Meeting> get pastMeetings {
    final now = DateTime.now();
    return _meetings.where((m) => m.end.isBefore(now)).toList()
      ..sort((a, b) => b.start.compareTo(a.start)); // Newest first for history
  }

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

  Future<void> respondToInvite(int inviteId, String status) async {
    try {
      _isLoading = true;
      notifyListeners();
      await _apiService.respondToInvite(inviteId, status);
      await fetchMyMeetings(); // Refresh list
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
