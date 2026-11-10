import 'dart:convert';
import 'dart:typed_data';

import 'package:diemdanh/core/api_client.dart';
import 'package:diemdanh/core/token_store.dart';
import 'package:dio/dio.dart';

typedef Reply = (int status, Object body);

/// HTTP giả: [handler] nhận request, trả (status, json). [calls] ghi lại "METHOD path token".
class FakeHttp implements HttpClientAdapter {
  FakeHttp(this.handler);
  final Reply Function(RequestOptions o) handler;
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) async {
    calls.add('${o.method} ${o.path} ${o.headers['Authorization'] ?? '-'}');
    final (status, body) = handler(o);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object> apiErr(String code, String message) => {
      'error': {'code': code, 'message': message, 'details': {}}
    };

ApiClient fakeClient(FakeHttp http, {TokenStore? store, void Function()? onLoggedOut}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = http;
  return ApiClient(store ?? MemoryTokenStore(), dio: dio, onLoggedOut: onLoggedOut);
}
