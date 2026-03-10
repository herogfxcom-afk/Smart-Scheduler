import 'package:flutter/material.dart';
import '../core/api/api_service.dart';

class GroupParticipant {
  final int id;
  final int telegramId;
  final String? username;
  final String? firstName;
  final String? photoUrl;
  final String? email;
  final bool isSynced;

  GroupParticipant({
    required this.id,
    required this.telegramId,
    this.username,
    this.firstName,
    this.photoUrl,
    this.email,
    required this.isSynced,
  });

  factory GroupParticipant.fromJson(Map<String, dynamic> json) {
    return GroupParticipant(
      id: json['id'],
      telegramId: json['telegram_id'],
      username: json['username'],
      firstName: json['first_name'],
      photoUrl: json['photo_url'],
      email: json['email'],
      isSynced: json['is_synced'] ?? false,
    );
  }
}

class GroupProvider with ChangeNotifier {
  final ApiService _apiService;
  
  String? _chatId;
  List<GroupParticipant> _participants = [];
  bool _isLoading = false;
  String? _error;

  GroupProvider(this._apiService);

  String? get chatId => _chatId;
  List<GroupParticipant> get participants => _participants;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void setChatId(String? id) {
    if (id == null || id.isEmpty) return;
    
    String finalId = id.trim();
    
    // Handle Telegram invite links
    // e.g., https://t.me/+cZuAHkVHFS43YTIi or https://t.me/joinchat/...
    if (finalId.contains("t.me/")) {
      if (finalId.contains("+")) {
         final inviteParts = finalId.split("+");
         if (inviteParts.length > 1) finalId = inviteParts.last;
      } else if (finalId.contains("joinchat/")) {
         final inviteParts = finalId.split("joinchat/");
         if (inviteParts.length > 1) finalId = inviteParts.last;
      }
    }
    
    bool isNewId = _chatId != finalId;
    _chatId = finalId;
    
    if (isNewId) {
      _participants = []; // Only reset list if it's a completely different group
    }
    
    notifyListeners();
    
    if (_chatId != null) {
      // Always sync to ensure membership is verified on backend
      syncWithGroup();
    }
  }

  Future<void> syncWithGroup() async {
    if (_chatId == null) return;
    
    try {
      _isLoading = true;
      notifyListeners();

      // 1. Tell backend we are in this group (allowing both numeric and alphanumeric tokens)
      await _apiService.post('/groups/sync', {
        'chat_id': _chatId!,
        'title': 'Telegram Group',
      });
      
      // 2. Fetch all participants
      await fetchParticipants();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchParticipants() async {
    if (_chatId == null) return;
    
    try {
      print("DEBUG: Fetching participants for chat_id: $_chatId");
      final response = await _apiService.get('/groups/$_chatId/participants'); // Use string chat_id directly
      _participants = (response.data as List)
          .map((p) => GroupParticipant.fromJson(p))
          .toList();
      _error = null;
      print("DEBUG: Synced with group. Participants: ${_participants.length}");
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      print("ERROR: Failed to fetch participants for chat_id $_chatId: $e");
      notifyListeners();
    }
  }
}
