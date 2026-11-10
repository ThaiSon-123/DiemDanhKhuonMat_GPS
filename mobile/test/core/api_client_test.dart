import 'package:diemdanh/core/api_error.dart';
import 'package:diemdanh/core/token_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_http.dart';

void main() {
  test('AUTH_TOKEN_EXPIRED: refresh đúng 1 lần rồi gửi lại với token mới', () async {
    final store = MemoryTokenStore()..save('old', 'r1');
    final http = FakeHttp((o) {
      if (o.path == '/auth/refresh') return (200, {'access_token': 'new', 'refresh_token': 'r2'});
      if (o.headers['Authorization'] == 'Bearer old') return (401, apiErr('AUTH_TOKEN_EXPIRED', 'Hết hạn'));
      return (200, {'ok': true});
    });
    final api = fakeClient(http, store: store);

    expect(await api.get('/me'), {'ok': true});
    expect(http.calls, ['GET /me Bearer old', 'POST /auth/refresh -', 'GET /me Bearer new']);
    expect(await store.refresh, 'r2');
  });

  test('refresh thất bại thì xóa token và đăng xuất, không lặp vô hạn', () async {
    final store = MemoryTokenStore()..save('old', 'r1');
    var loggedOut = 0;
    final http = FakeHttp((o) => o.path == '/auth/refresh'
        ? (401, apiErr('AUTH_TOKEN_REVOKED', 'Thu hồi'))
        : (401, apiErr('AUTH_TOKEN_EXPIRED', 'Hết hạn')));
    final api = fakeClient(http, store: store, onLoggedOut: () => loggedOut++);

    await expectLater(api.get('/me'), throwsA(isA<ApiError>()));
    expect(await store.access, isNull);
    expect(loggedOut, greaterThan(0));
    expect(http.calls.where((c) => c.startsWith('POST /auth/refresh')).length, 1);
  });

  test('AUTH_TOKEN_REVOKED: xóa token và gọi onLoggedOut', () async {
    final store = MemoryTokenStore()..save('a', 'r');
    var loggedOut = false;
    final api = fakeClient(FakeHttp((_) => (401, apiErr('AUTH_TOKEN_REVOKED', 'Phiên đăng nhập đã bị thu hồi'))),
        store: store, onLoggedOut: () => loggedOut = true);

    await expectLater(api.get('/me'), throwsA(isA<ApiError>().having((e) => e.code, 'code', 'AUTH_TOKEN_REVOKED')));
    expect(loggedOut, isTrue);
    expect(await store.access, isNull);
  });

  test('đọc envelope lỗi thành ApiError', () async {
    final api = fakeClient(FakeHttp((_) => (409, {
          'error': {'code': 'SESSION_CLOSED', 'message': 'Phiên điểm danh đã đóng', 'details': {'x': 1}}
        })));

    await expectLater(
        api.post('/sessions/1/challenge'),
        throwsA(isA<ApiError>()
            .having((e) => e.status, 'status', 409)
            .having((e) => e.code, 'code', 'SESSION_CLOSED')
            .having((e) => e.message, 'message', 'Phiên điểm danh đã đóng')
            .having((e) => e.details, 'details', {'x': 1})));
  });
}
