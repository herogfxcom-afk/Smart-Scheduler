import 'package:flutter/material.dart';
import '../core/api/api_service.dart';
import '../models/time_slot.dart';
import '../models/user.dart';

class SchedulerProvider extends ChangeNotifier {
  final ApiService _apiService;

  SchedulerProvider(this._apiService);

  List<TimeSlot> _suggestedSlots = [];
  bool _isLoading = false;
  String? _error;

  List<User> _allUsers = [];
  List<int> _selectedParticipants = [];

  List<User> get allUsers => _allUsers;
  List<int> get selectedParticipants => _selectedParticipants;
  List<TimeSlot> get suggestedSlots => _suggestedSlots;
  bool get isLoading => _isLoading;

  Future<void> fetchUsers() async {
    try {
      final response = await _apiService.get('/users');
      final List<dynamic> usersData = response.data;
      _allUsers = usersData.map((u) => User.fromJson(u)).toList();
      notifyListeners();
    } catch (e) {
      print("Fetch Users Error: $e");
    }
  }

  void toggleParticipant(int tgId) {
    if (_selectedParticipants.contains(tgId)) {
      _selectedParticipants.remove(tgId);
    } else {
      _selectedParticipants.add(tgId);
    }
    notifyListeners();
  }

  Future<void> findBestTime(List<int> telegramIds) async {
    if (telegramIds.isEmpty) return;
    await fetchCommonSlots(telegramIds);
  }

  Future<void> fetchCommonSlots(List<int> telegramIds) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.post('/calendar/free-slots', {
        'telegram_ids': telegramIds,
        'tz_offset': DateTime.now().timeZoneOffset.inHours,
      });
      final List<dynamic> data = response.data['free_slots'] ?? [];
      _suggestedSlots = data.map((e) => TimeSlot.fromJson(e)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createMeeting({
    required String title,
    required TimeSlot slot,
    List<String>? attendeeEmails,
    String? chatId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 1. Logging for debug
      print("DEBUG: Booking slot (Local): ${slot.start} - ${slot.end}");
      print("DEBUG: Booking slot (UTC): ${slot.start.toUtc()} - ${slot.end.toUtc()}");

      // 2. Optimistic Update: Remove from suggested list immediately
      final originalSlots = List<TimeSlot>.from(_suggestedSlots);
      _suggestedSlots.removeWhere((s) => s.start == slot.start && s.end == slot.end);
      notifyListeners();

      // 3. Enhanced Idempotency key (includes end time and current timestamp for uniqueness)
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final idempotencyKey = chatId != null
          ? "group_${chatId}_${slot.start.millisecondsSinceEpoch}_${slot.end.millisecondsSinceEpoch}"
          : "user_${slot.start.millisecondsSinceEpoch}_${timestamp}";

      final response = await _apiService.post('/meeting/create', {
        'title': title,
        'start': slot.start.toUtc().toIso8601String(),
        'end': slot.end.toUtc().toIso8601String(),
        'attendee_emails': attendeeEmails ?? [],
        'idempotency_key': idempotencyKey,
      });

      print("DEBUG: Server response: ${response.data}");
      return true;
    } catch (e) {
      print("DEBUG: createMeeting Error: $e");
      _error = e.toString();
      // Rollback optimistic update if failed
      await fetchCommonSlots(_selectedParticipants); 
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> finalizeMeeting({
    required String chatId,
    required String timeStr,
  }) async {
    try {
      await _apiService.post('/meeting/finalize', {
        'chat_id': chatId,
        'time_str': timeStr,
      });
      return true;
    } catch (e) {
      print("Finalize Meeting Error: $e");
      return false;
    }
  }
}
