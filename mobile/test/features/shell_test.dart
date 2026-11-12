import 'package:diemdanh/features/auth/change_password_page.dart';
import 'package:diemdanh/features/lecturer/lecturer_nav.dart';
import 'package:diemdanh/features/lecturer/lecturer_shell.dart';
import 'package:diemdanh/ui/web_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../inter_font.dart';
import 'enroll_test.dart' show pump;

void main() {
  setUpAll(loadInterFont);

  for (final (w, sidebar) in const [(1280.0, true), (390.0, false)]) {
    testWidgets('khung giảng viên ${w.toInt()} px: ${sidebar ? 'có thanh bên, ẩn dock' : 'giữ dock điện thoại'}', (t) async {
      await pump(t, (s) => LecturerShell(session: s..user = {'full_name': 'TS. Trần Minh Đức', 'username': 'gv.duc', 'role': 'lecturer'},
          location: '/lecturer/faces', child: LecturerFacesPage(session: s)), (o) => (200, []), size: Size(w, 800));
      expect(find.byType(WebSidebar), sidebar ? findsOneWidget : findsNothing);
      expect(find.text('Chiếu mã phòng'), sidebar ? findsOneWidget : findsNothing);
      expect(find.text('Duyệt mặt'), sidebar ? findsNothing : findsOneWidget); // nhãn trên dock
    });
  }

  testWidgets('chọn phiên để chiếu: chỉ phiên đang mở, phiên tắt mã phòng thì không chiếu được', (t) async {
    await pump(t, (s) => ProjectPickerPage(session: s), (o) => (200, [
          {'id': 1, 'code': 'IT4060', 'name': 'Học máy', 'semester': '2026-1',
            'open_session': {'id': 41, 'expires_at': DateTime.now().add(const Duration(minutes: 5)).toUtc().toIso8601String(), 'room_check': true}},
          {'id': 2, 'code': 'IT3100', 'name': 'CTDL', 'semester': '2026-1',
            'open_session': {'id': 42, 'expires_at': DateTime.now().add(const Duration(minutes: 5)).toUtc().toIso8601String(), 'room_check': false}},
          {'id': 3, 'code': 'IT9999', 'name': 'Không mở', 'semester': '2026-1', 'open_session': null},
        ]), settle: false);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Học máy'), findsOneWidget);
    expect(find.text('Không mở'), findsNothing);
    expect(find.text('Phiên này không bật mã phòng'), findsOneWidget);
    final buttons = t.widgetList<FilledButton>(find.widgetWithText(FilledButton, 'Chiếu mã')).toList();
    expect([for (final b in buttons) b.onPressed != null], [true, false]);
  });

  testWidgets('tự đổi mật khẩu: nhãn "Mật khẩu hiện tại", đổi xong đóng màn', (t) async {
    late Map body;
    await pump(t, (s) => Builder(builder: (c) => Scaffold(
          body: Center(child: TextButton(onPressed: () => ChangePasswordPage.open(c, s), child: const Text('mở'))),
        )), (o) {
      body = o.data as Map;
      return (200, {'access_token': 'a', 'refresh_token': 'r'});
    });
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    expect(find.text('Đổi mật khẩu'), findsOneWidget);
    expect(find.text('Mật khẩu hiện tại'), findsOneWidget);
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'cu123456');
    await t.enterText(fields.at(1), 'Moi12345678');
    await t.enterText(fields.at(2), 'Moi12345678');
    await t.tap(find.text('Lưu mật khẩu'));
    await t.pumpAndSettle();
    expect(body, {'old_password': 'cu123456', 'new_password': 'Moi12345678'});
    expect(find.text('mở'), findsOneWidget); // đã quay lại
    expect(find.textContaining('Đã đổi mật khẩu'), findsOneWidget);
  });
}
