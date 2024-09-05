
import 'dart:io';

import 'package:serinus/serinus.dart';

class TestSession implements HttpSession {

  final Map _data = {};

  @override
  operator [](Object? key) {
    return _data[key];
  }

  @override
  void operator []=(key, value) {
    _data[key] = value;
  }

  @override
  void addAll(Map other) {
    _data.addAll(other);
  }

  @override
  void addEntries(Iterable<MapEntry> newEntries) {
    _data.addEntries(newEntries);
  }

  @override
  Map<RK, RV> cast<RK, RV>() {
    return _data.cast<RK, RV>();
  }

  @override
  void clear() {
    _data.clear();
  }

  @override
  bool containsKey(Object? key) {
    return _data.containsKey(key);
  }

  @override
  bool containsValue(Object? value) {
    return _data.containsValue(value);
  }

  @override
  void destroy() {
    clear();
  }

  @override
  Iterable<MapEntry> get entries => _data.entries;

  @override
  void forEach(void Function(dynamic key, dynamic value) action) {
    _data.forEach(action);
  }

  @override
  String get id => 'test-session';

  @override
  bool get isEmpty => _data.isEmpty;


  @override
  bool get isNew => true;

  @override
  bool get isNotEmpty => _data.isNotEmpty;

  @override
  Iterable get keys => _data.keys;

  @override
  int get length => _data.length;

  @override
  Map<K2, V2> map<K2, V2>(MapEntry<K2, V2> Function(dynamic key, dynamic value) convert) {
    return _data.map(convert);
  }

  @override
  set onTimeout(void Function() callback) {
    
  }

  @override
  putIfAbsent(key, Function() ifAbsent) {
    return _data.putIfAbsent(key, ifAbsent);
  }

  @override
  remove(Object? key) {
    return _data.remove(key);
  }

  @override
  void removeWhere(bool Function(dynamic key, dynamic value) test) {
    _data.removeWhere(test);
  }

  @override
  update(key, Function(dynamic value) update, {Function()? ifAbsent}) {
    return _data.update(key, update, ifAbsent: ifAbsent);
  }

  @override
  void updateAll(Function(dynamic key, dynamic value) update) {
    _data.updateAll(update);
  }

  @override
  Iterable get values => _data.values;
  
}

class TestRequest extends IncomingMessage {

  TestRequest(
    this._method, 
    this.uri,
    {
      this.body,
      this.contentLength = 0,
      this.headers = const {},
      this.query = const {},
      this.data = const {},
    }
  ): contentType = ContentType.json,
      path = uri.path,
      session = Session(TestSession());

  @override
  dynamic operator [](String key) {
    return data[key];
  }

  @override
  void operator []=(String key, value) {
    data[key] = value;
  }

  @override
  void addData(String key, value) {
    data[key] = value;
  }

  final HttpMethod _method;

  @override
  final Body? body;

  @override
  HttpConnectionInfo? get clientInfo => null;

  @override
  final int contentLength;

  @override
  ContentType contentType;

  final Map<String, dynamic> data;

  @override
  dynamic getData(String key) {
    return data[key];
  }

  @override
  final Map<String, dynamic> headers;

  @override
  String get id => 'test-request';

  @override
  String get method => _method.toString();

  Map<String, dynamic> _params = {};

  @override
  Map<String, dynamic> get params => _params;

  set params(Map<String, dynamic> value) {
    _params = value;
  }

  @override
  Future<void> parseBody() async {
    return;
  }

  @override
  String path;

  @override
  final Map<String, dynamic> query;

  @override
  final Session session;

  @override
  final Uri uri;

}

class TestResponse {

  final dynamic data;

  final ResponseProperties properties;

  TestResponse(this.data, this.properties);

}