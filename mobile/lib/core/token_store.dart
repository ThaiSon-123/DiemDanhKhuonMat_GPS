import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lưu access/refresh token. Bản chạy thật dùng secure storage; test dùng [MemoryTokenStore].
abstract class TokenStore {
  Future<String?> get access;
  Future<String?> get refresh;
  Future<void> save(String access, String refresh);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  final _s = const FlutterSecureStorage();

  @override
  Future<String?> get access => _s.read(key: 'access_token');
  @override
  Future<String?> get refresh => _s.read(key: 'refresh_token');
  @override
  Future<void> save(String access, String refresh) async {
    await _s.write(key: 'access_token', value: access);
    await _s.write(key: 'refresh_token', value: refresh);
  }

  @override
  Future<void> clear() async {
    await _s.delete(key: 'access_token');
    await _s.delete(key: 'refresh_token');
  }
}

class MemoryTokenStore implements TokenStore {
  String? _a, _r;
  @override
  Future<String?> get access async => _a;
  @override
  Future<String?> get refresh async => _r;
  @override
  Future<void> save(String access, String refresh) async {
    _a = access;
    _r = refresh;
  }
  @override
  Future<void> clear() async {
    _a = null;
    _r = null;
  }
}
