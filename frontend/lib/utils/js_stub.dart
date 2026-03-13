// stub for dart:js_interop and other web interops
class JS {
  final String name;
  const JS(this.name);
}

class JSObject {}
class JSString {}
class JSNumber {}

extension JSStringExtension on JSString {
  String get toDart => '';
}

extension JSNumberExtension on JSNumber {
  int get toDartInt => 0;
  double get toDartDouble => 0.0;
}

extension JSObjectExtension on JSObject {
  Object? getProperty(Object key) => null;
  Object? callMethod(Object method, [Object? arg1, Object? arg2]) => null;
  bool isA<T>() => false;
}

extension ObjectToJSExtension on Object? {
  bool isA<T>() => false;
}

extension StringToJS on String {
  Object get toJS => this;
}

Map<String, dynamic> globalContext = {};

// from web_interop_stub
JSObject? get webApp => null;
Map<String, dynamic> get window => {};
