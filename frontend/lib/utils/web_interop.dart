import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window.Telegram.WebApp')
external JSObject? get webApp;

@JS('window')
external JSObject get window;
