import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider with ChangeNotifier {
  Locale _locale = const Locale('ru');
  
  Locale get locale => _locale;

  LanguageProvider() {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = prefs.getString('language_code') ?? 'ru';
    _locale = Locale(langCode);
    notifyListeners();
  }

  final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'app_title': 'Magic Sync Dashboard',
      'welcome': 'Hello',
      'setup_profile': 'Set up your profile',
      'group_sync': 'Group Sync',
      'connected_calendars': 'Connected Calendars',
      'services_settings': 'Services & Settings',
      'invites': 'Invitations',
      'upcoming_meetings': 'Upcoming Meetings',
      'no_meetings': 'No meetings scheduled',
      'work_hours': 'Work Hours',
      'sync': 'Sync',
      'syncing': 'Syncing...',
      'update_calendar': 'Update Calendar',
      'connect_group': 'Connect Group',
      'team_planning': 'For team planning',
      'group_id_hint': 'Group ID or link',
      'connect_btn': 'Connect',
      'participants_online': 'Participants online',
      'add_bot': 'Add bot to group',
      'accept': 'Accept',
      'decline': 'Decline',
      'close': 'Close',
      'setup_availability': 'Setup availability',
    },
    'ru': {
      'app_title': 'Magic Sync Dashboard',
      'welcome': 'Привет',
      'setup_profile': 'Настройте ваш профиль',
      'group_sync': 'Групповая синхронизация',
      'connected_calendars': 'Подключенные календари',
      'services_settings': 'Сервисы и настройки',
      'invites': 'Приглашения',
      'upcoming_meetings': 'Ближайшие встречи',
      'no_meetings': 'Запланированных встреч нет',
      'work_hours': 'Рабочие часы',
      'sync': 'Синхронизация',
      'syncing': 'В процессе...',
      'update_calendar': 'Обновить календарь',
      'connect_group': 'Подключить группу',
      'team_planning': 'Для командного планирования',
      'group_id_hint': 'ID группы или ссылка',
      'connect_btn': 'Подключить',
      'participants_online': 'Участников онлайн',
      'add_bot': 'Добавить бота в группу',
      'accept': 'Принять',
      'decline': 'Отклонить',
      'close': 'Закрыть',
      'setup_availability': 'Настроить график',
    },
    'uk': {
      'app_title': 'Magic Sync Dashboard',
      'welcome': 'Привіт',
      'setup_profile': 'Налаштуйте ваш профіль',
      'group_sync': 'Групова синхронізація',
      'connected_calendars': 'Підключені календарі',
      'services_settings': 'Сервіси та налаштування',
      'invites': 'Запрошення',
      'upcoming_meetings': 'Найближчі зустрічі',
      'no_meetings': 'Запланованих зустрічей немає',
      'work_hours': 'Робочі години',
      'sync': 'Синхронізація',
      'syncing': 'У процесі...',
      'update_calendar': 'Оновити календар',
      'connect_group': 'Підключити групу',
      'team_planning': 'Для командного планування',
      'group_id_hint': 'ID групи або посилання',
      'connect_btn': 'Підключити',
      'participants_online': 'Учасників онлайн',
      'add_bot': 'Додати бота до групи',
      'accept': 'Прийняти',
      'decline': 'Відхилити',
      'close': 'Закрити',
      'setup_availability': 'Налаштувати графік',
    },
  };

  String translate(String key) {
    return _localizedValues[_locale.languageCode]?[key] ?? key;
  }

  Future<void> setLocale(String langCode) async {
    _locale = Locale(langCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', langCode);
    notifyListeners();
  }
}
