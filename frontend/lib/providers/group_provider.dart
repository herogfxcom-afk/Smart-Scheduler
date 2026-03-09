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
    if (_chatId == id) return;
    _chatId = id;
    _participants = []; // Reset on change
    notifyListeners();
    if (_chatId != null) {
      syncWithGroup();
    }
  }

  Future<void> syncWithGroup() async {
    if (_chatId == null) return;
    
    try {
      _isLoading = true;
      notifyListeners();

      // 1. Tell backend we are in this group
      await _apiService.post('/groups/sync', {
        'chat_id': int.tryParse(_chatId!) ?? _chatId.hashCode,
        'title': 'Telegram Group', // Title extraction could be improved later
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
      final response = await _apiService.get('/groups/${int.tryParse(_chatId!) ?? _chatId.hashCode}/participants');
      _participants = (response.data as List).map((p) => GroupParticipant.fromJson(p)).toList();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
}
