import 'package:diemdanh/core/session.dart';
import 'package:diemdanh/features/admin/admin_shell.dart';
import 'package:diemdanh/features/lecturer/lecturer_home_page.dart';
import 'package:diemdanh/features/student/student_home_page.dart';
import 'package:diemdanh/ui/neo_parts.dart';
import 'package:diemdanh/ui/theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_http.dart';
import '../inter_font.dart';

/// Chỉ tmp_shots_test bật: chụp ảnh từng trang để so với canvas.
bool shots = false;

final _soon = DateTime.now().toUtc().add(const Duration(minutes: 7)).toIso8601String();

Future<FakeHttp> _pump(WidgetTester t, Widget Function(Session) page, Reply Function(RequestOptions) handler,
    {Size size = const Size(390, 844), Map<String, dynamic>? user}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final http = FakeHttp(handler);
  final session = Session(fakeClient(http))..user = user ?? {'full_name': 'Nguyễn Văn An', 'username': 'sv001'};
  await t.pumpWidget(MaterialApp(theme: appTheme(), home: page(session)));
  // Có đồng hồ đếm ngược chạy mỗi giây nên không dùng pumpAndSettle.
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
  if (shots) {
    await t.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/${t.testDescription.hashCode}.png'));
  }
  return http;
}

void main() {
  setUpAll(loadInterFont);

  test('initials bỏ học hàm, lấy chữ đầu và chữ cuối', () {
    expect(initials('Nguyễn Văn An'), 'NA');
    expect(initials('TS. Trần Minh Đức'), 'TĐ');
    expect(initials('An'), 'A');
    expect(initials(''), '?');
  });

  testWidgets('trang chủ sinh viên: lời chào, trạng thái khuôn mặt, lớp đang mở, danh sách lớp', (t) async {
    await _pump(t, (s) => StudentHomePage(session: s), (o) => switch (o.path) {
          '/me' => (200, {
              'id': 1, 'role': 'student', 'username': 'sv001', 'full_name': 'Nguyễn Văn An', 'student_code': 'SV001',
              'must_change_password': false, 'consent': {'current_version': 'v1', 'accepted': true},
              'face': {'status': 'approved', 'reject_reason': null, 'model_ok': true, 'pending_update': false},
            }),
          '/me/classes' => (200, [
              {'id': 3, 'code': 'IT4060', 'name': 'Học máy', 'semester': '2026-1', 'lecturer_name': 'TS. Trần Minh Đức',
               'open_session': {'id': 41, 'expires_at': _soon, 'room_check': true}},
              {'id': 4, 'code': 'IT3100', 'name': 'Lập trình hướng đối tượng', 'semester': '2026-1',
               'lecturer_name': 'ThS. Phạm Thu Trang', 'open_session': null},
            ]),
          _ => (404, apiErr('NOT_FOUND', 'Không tìm thấy')),
        });
    expect(find.text('Xin chào, Nguyễn Văn An!'), findsOneWidget);
    expect(find.text('Khuôn mặt đã duyệt'), findsOneWidget);
    expect(find.text('Học kỳ 2026-1'), findsOneWidget);
    expect(find.text('ĐANG MỞ ĐIỂM DANH'), findsOneWidget);
    expect(find.text('Quét mã QR trên máy chiếu'), findsOneWidget);  // phiên bật mã phòng
    expect(find.textContaining(RegExp(r'^0[67]:\d\d$')), findsOneWidget);  // đếm ngược ~7 phút
    expect(find.text('2 môn'), findsOneWidget);
    await t.drag(find.byType(ListView), const Offset(0, -600));
    await t.pump();
    expect(find.text('Lập trình hướng đối tượng'), findsOneWidget);
  });

  testWidgets('trang chủ sinh viên: lỗi mạng thì hiện thông điệp và nút thử lại', (t) async {
    await _pump(t, (s) => StudentHomePage(session: s), (_) => (500, apiErr('INTERNAL', 'Máy chủ gặp lỗi')));
    expect(find.text('Máy chủ gặp lỗi'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
  });

  testWidgets('trang chủ giảng viên: phiên đang mở có sĩ số và đếm ngược', (t) async {
    await _pump(t, (s) => LecturerHomePage(session: s), user: {'full_name': 'TS. Trần Minh Đức', 'username': 'ducdm'},
        (o) => (200, [
              {'id': 3, 'code': 'IT4060', 'name': 'Học máy', 'semester': '2026-1', 'student_count': 62,
               'open_session': {'id': 41, 'expires_at': _soon, 'room_check': true}},
              {'id': 5, 'code': 'IT4343', 'name': 'Thị giác máy tính', 'semester': '2026-1', 'student_count': 48,
               'open_session': null},
            ]));
    expect(find.text('PHIÊN ĐANG MỞ'), findsOneWidget);
    expect(find.text('62 SV'), findsOneWidget);
    expect(find.text('2 lớp'), findsOneWidget);
    expect(find.text('Mở phiên'), findsOneWidget);  // chỉ lớp không có phiên mới có nút mở
    expect(find.text('TĐ'), findsOneWidget);
  });

  testWidgets('quản trị: bảng người dùng, số liệu, đặt lại mật khẩu hiện mật khẩu tạm', (t) async {
    final http = await _pump(t, (s) => AdminShell(session: s), size: const Size(1280, 900),
        user: {'full_name': 'Quản trị viên khoa', 'username': 'admin'}, (o) {
      if (o.path == '/admin/users' && o.queryParameters['size'] == 1) {
        final q = o.queryParameters;
        final n = q['active'] == false ? 3 : q['face'] == 'none' ? 37 : q['role'] == 'lecturer' ? 18 : 412;
        return (200, {'items': [], 'total': n});
      }
      if (o.path == '/admin/users') {
        return (200, {
          'total': 2,
          'items': [
            {'id': 7, 'role': 'student', 'username': 'sv001', 'full_name': 'Nguyễn Văn An', 'student_code': 'SV001',
             'is_active': true, 'face_status': 'pending'},
            {'id': 8, 'role': 'lecturer', 'username': 'ducdm', 'full_name': 'TS. Trần Minh Đức', 'student_code': null,
             'is_active': false, 'face_status': 'none'},
          ],
        });
      }
      if (o.path == '/admin/users/7/reset-password') return (200, {'temp_password': 'Ab3dEf7hJk'});
      return (404, apiErr('NOT_FOUND', 'Không tìm thấy'));
    });
    await t.pump();
    expect(find.text('Người dùng'), findsWidgets);
    for (final n in ['412', '18', '37', '3']) {
      expect(find.text(n), findsOneWidget);
    }
    expect(find.text('Chờ duyệt'), findsOneWidget);
    expect(find.text('Không áp dụng'), findsOneWidget);
    expect(find.text('Vô hiệu hóa'), findsOneWidget);
    expect(find.text('Hiển thị 1–2 trong 2 người dùng'), findsOneWidget);

    await t.tap(find.text('Đặt lại mật khẩu').first);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Đặt lại'));
    await t.pumpAndSettle();
    expect(find.text('Ab3dEf7hJk'), findsOneWidget);
    expect(http.calls.any((c) => c.startsWith('POST /admin/users/7/reset-password')), isTrue);
  });
}
