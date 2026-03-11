import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window.Telegram.WebApp')
external JSObject? get _webApp;

class TelegramService {
  static final TelegramService _instance = TelegramService._internal();
  factory TelegramService() => _instance;
  TelegramService._internal();

  bool get isReady {
    try {
      return _webApp != null;
    } catch (_) {
      return false;
    }
  }

  void init() {
    if (isReady) {
      try {
        _webApp!.callMethod('expand'.toJS);
        _webApp!.callMethod('ready'.toJS);
        _webApp!.callMethod('enableClosingConfirmation'.toJS);
      } catch (_) {}
    }
  }

  Map<String, dynamic> getUser() {
    if (!isReady) return {'id': 0, 'first_name': 'Guest'};
    try {
      final initDataUnsafe = _webApp!.getProperty('initDataUnsafe'.toJS) as JSObject?;
      if (initDataUnsafe != null) {
        final user = initDataUnsafe.getProperty('user'.toJS) as JSObject?;
        if (user != null) {
          return {
            'id': (user.getProperty('id'.toJS) as JSNumber).toDartInt,
            'first_name': (user.getProperty('first_name'.toJS) as JSString).toDart,
            'last_name': user.getProperty('last_name'.toJS).isA<JSString>() 
                ? (user.getProperty('last_name'.toJS) as JSString).toDart : null,
            'username': user.getProperty('username'.toJS).isA<JSString>() 
                ? (user.getProperty('username'.toJS) as JSString).toDart : null,
            'photo_url': user.getProperty('photo_url'.toJS).isA<JSString>() 
                ? (user.getProperty('photo_url'.toJS) as JSString).toDart : null,
          };
        }
      }
    } catch (_) {}
    return {'id': 0, 'first_name': 'Unknown'};
  }

  String? getChatTitle() {
    if (!isReady) return null;
    try {
      final initDataUnsafe = _webApp!.getProperty('initDataUnsafe'.toJS) as JSObject?;
      if (initDataUnsafe != null) {
        final chat = initDataUnsafe.getProperty('chat'.toJS) as JSObject?;
        if (chat != null) {
          final titleObj = chat.getProperty('title'.toJS);
          if (titleObj != null && titleObj.isA<JSString>()) {
            return (titleObj as JSString).toDart;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  String get initData {
    if (!isReady) return '';
    try {
      final data = _webApp!.getProperty('initData'.toJS);
      if (data != null && data.isA<JSString>()) {
        return (data as JSString).toDart;
      }
    } catch (_) {}
    return '';
  }

  void openLink(String url) {
    if (isReady) {
      try {
        _webApp!.callMethod('openLink'.toJS, url.toJS);
        return;
      } catch (_) {}
    }
    // Fallback logic in caller
  }

  void close({Map<String, dynamic>? data}) {
    if (isReady) {
      try {
        if (data != null) {
          // Send data back to the bot before closing
          _webApp!.callMethod('sendData'.toJS, data.toString().toJS);
        }
        _webApp!.callMethod('close'.toJS);
      } catch (e) {
        print("Error closing WebApp: $e");
      }
    }
  }

  void showPopup({required String message, String? title}) {
    if (isReady) {
      try {
        _webApp!.callMethod('showAlert'.toJS, message.toJS);
      } catch (_) {}
    }
  }

  void hapticFeedback() {
    if (isReady) {
      try {
        final haptic = _webApp!.getProperty('HapticFeedback'.toJS) as JSObject?;
        haptic?.callMethod('impactOccurred'.toJS, 'medium'.toJS);
      } catch (_) {}
    }
  }

  String? getStartParam() {
    if (!isReady) return null;
    try {
      final initDataUnsafe = _webApp!.getProperty('initDataUnsafe'.toJS) as JSObject?;
      if (initDataUnsafe != null) {
        final startParam = initDataUnsafe.getProperty('start_param'.toJS);
        if (startParam != null && startParam.isA<JSString>()) {
          return (startParam as JSString).toDart;
        }
      }
    } catch (e) {
      print("Error getting start_param: $e");
    }
    return null;
  }

  /// Parses initData from URI (Recommended approach for reliability)
  Map<String, String>? parseInitDataFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      
      // Look for tgWebAppData or just startapp directly
      String? dataRaw = uri.queryParameters['tgWebAppData'];
      
      // Case 1: Standard tgWebAppData (found in direct frame URL)
      if (dataRaw != null) {
        final decoded = Uri.decodeComponent(dataRaw);
        return Uri.splitQueryString(decoded);
      }
      
      // Case 2: In fragment (sometimes Flutter HashStrategy puts it there)
      if (uri.fragment.contains('tgWebAppData=')) {
         final fragmentQuery = uri.fragment.contains('?') 
             ? uri.fragment.split('?').last 
             : uri.fragment;
         final fragmentParts = Uri.splitQueryString(fragmentQuery);
         final fragmentDataRaw = fragmentParts['tgWebAppData'];
         if (fragmentDataRaw != null) {
           return Uri.splitQueryString(Uri.decodeComponent(fragmentDataRaw));
         }
      }
    } catch (e) {
      print("Error parsing init data from URL: $e");
    }
    return null;
  }

  String? getStartParamFromUrl(String url) {
    // 1. Try tgWebAppData parsing
    final data = parseInitDataFromUrl(url);
    if (data != null && data['start_param'] != null) {
      return data['start_param'];
    }
    
    // 2. Fallback to direct startapp query param
    final uri = Uri.parse(url);
    if (uri.queryParameters['startapp'] != null) {
      return uri.queryParameters['startapp'];
    }
    
    // 3. Fallback to fragment startapp
    if (uri.fragment.contains('startapp=')) {
       final fragmentQuery = uri.fragment.contains('?') 
           ? uri.fragment.split('?').last 
           : uri.fragment;
       final parts = Uri.splitQueryString(fragmentQuery);
       return parts['startapp'];
    }
    
    return null;
  }
}
