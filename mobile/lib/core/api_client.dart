import 'package:dio/dio.dart';

import 'api_error.dart';
import 'token_store.dart';

const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8000');

class ApiClient {
  ApiClient(this.store, {String baseUrl = apiUrl, this.onLoggedOut, Dio? dio})
      : dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 10))) {
    this.dio.interceptors.add(InterceptorsWrapper(onRequest: _attachToken, onError: _onError));
  }

  final TokenStore store;
  final Dio dio;
  void Function()? onLoggedOut;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _send(path, 'GET', query: query);
  Future<dynamic> post(String path, {Object? data}) => _send(path, 'POST', data: data);
  Future<dynamic> patch(String path, {Object? data}) => _send(path, 'PATCH', data: data);
  Future<dynamic> delete(String path) => _send(path, 'DELETE');

  Future<dynamic> _send(String path, String method, {Object? data, Map<String, dynamic>? query}) async {
    try {
      final r = await dio.request(path, data: data, queryParameters: query, options: Options(method: method));
      return r.data;
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  Future<void> _attachToken(RequestOptions o, RequestInterceptorHandler h) async {
    final token = await store.access;
    if (token != null && o.extra['skipAuth'] != true) o.headers['Authorization'] = 'Bearer $token';
    h.next(o);
  }

  Future<void> _onError(DioException e, ErrorInterceptorHandler h) async {
    final code = ApiError.fromDio(e).code;
    if (code == 'AUTH_TOKEN_REVOKED') {
      await _logout();
    } else if (code == 'AUTH_TOKEN_EXPIRED' && e.requestOptions.extra['retried'] != true) {
      final refreshed = await _refresh();
      if (refreshed != null) {
        final o = e.requestOptions..extra['retried'] = true;
        o.headers['Authorization'] = 'Bearer $refreshed';
        try {
          return h.resolve(await dio.fetch(o));
        } on DioException catch (again) {
          return h.next(again);
        }
      }
    }
    h.next(e);
  }

  /// Gọi /auth/refresh đúng một lần; thất bại thì đăng xuất. Trả access token mới hoặc null.
  Future<String?> _refresh() async {
    final refresh = await store.refresh;
    if (refresh == null) {
      await _logout();
      return null;
    }
    try {
      final r = await dio.post('/auth/refresh',
          data: {'refresh_token': refresh}, options: Options(extra: {'skipAuth': true, 'retried': true}));
      await store.save(r.data['access_token'], r.data['refresh_token']);
      return r.data['access_token'] as String;
    } on DioException {
      await _logout();
      return null;
    }
  }

  Future<void> _logout() async {
    await store.clear();
    onLoggedOut?.call();
  }
}
