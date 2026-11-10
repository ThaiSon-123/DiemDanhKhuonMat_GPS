import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_error.dart';

/// Người dùng đang đăng nhập. Router lắng nghe để điều hướng theo vai trò.
class Session extends ChangeNotifier {
  Session(this.api) {
    api.onLoggedOut = _clear;
  }

  final ApiClient api;
  Map<String, dynamic>? user;

  bool get loggedIn => user != null;
  String? get role => user?['role'] as String?;
  bool get mustChangePassword => user?['must_change_password'] == true;

  /// Mở app: có token thì lấy lại /me, lỗi thì coi như chưa đăng nhập.
  Future<void> restore() async {
    if (await api.store.access == null) return;
    try {
      user = Map<String, dynamic>.from(await api.get('/me'));
    } on ApiError {
      await api.store.clear();
      user = null;
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final r = await api.post('/auth/login', data: {'email': email, 'password': password});
    await api.store.save(r['access_token'], r['refresh_token']);
    user = Map<String, dynamic>.from(r['user']);
    notifyListeners();
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    final r = await api.post('/auth/change-password',
        data: {'old_password': oldPassword, 'new_password': newPassword});
    await api.store.save(r['access_token'], r['refresh_token']);
    user = {...?user, 'must_change_password': false};
    notifyListeners();
  }

  Future<void> logout() async {
    await api.store.clear();
    _clear();
  }

  void _clear() {
    user = null;
    notifyListeners();
  }
}
