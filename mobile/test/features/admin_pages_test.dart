import 'package:diemdanh/core/files.dart';
import 'package:diemdanh/core/session.dart';
import 'package:diemdanh/features/admin/audit_page.dart';
import 'package:diemdanh/features/admin/classes_page.dart';
import 'package:diemdanh/features/admin/import_page.dart';
import 'package:diemdanh/ui/theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_http.dart';
import '../inter_font.dart';

Future<FakeHttp> _pump(WidgetTester t, Widget Function(Session) page, Reply Function(RequestOptions) handler) async {
  t.view.physicalSize = const Size(1024, 980);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final http = FakeHttp(handler);
  final session = Session(fakeClient(http))..user = {'full_name': 'Quản trị viên khoa', 'username': 'admin'};
  await t.pumpWidget(MaterialApp(theme: appTheme(), home: Scaffold(body: page(session))));
  await t.pumpAndSettle();
  return http;
}

Map<String, Object> page(List<Map<String, Object?>> items) => {'items': items, 'total': items.length};

void main() {
  setUpAll(loadInterFont);

  test('classShort lấy chữ đầu tối đa 3 từ', () {
    expect(classShort('Học máy'), 'HM');
    expect(classShort('Tương tác người – máy'), 'TTN');
  });

  testWidgets('Lớp: chọn lớp xem sinh viên, thêm sinh viên theo mã, báo lỗi mã sai', (t) async {
    var enrolled = <Map<String, Object?>>[
      {'id': 7, 'full_name': 'Nguyễn Văn An', 'username': 'sv001', 'student_code': 'SV001', 'face_status': 'approved'},
    ];
    final http = await _pump(t, (s) => ClassesPage(session: s), (o) {
      final body = o.data is Map ? o.data as Map : const {};
      return switch ((o.method, o.path)) {
        ('GET', '/admin/classes') => (200, page([
            {'id': 3, 'code': 'IT4060', 'name': 'Học máy', 'semester': '2026-1', 'lecturer_id': 2,
             'lecturer_name': 'TS. Trần Minh Đức', 'student_count': enrolled.length, 'session_count': 10},
          ])),
        ('GET', '/admin/users') => (200, page([
            {'id': 2, 'full_name': 'TS. Trần Minh Đức', 'username': 'ducdm'},
          ])),
        ('GET', '/admin/enrollments') => (200, enrolled),
        ('POST', '/admin/enrollments') when body['student_code'] == 'SV404' => (422, {
            'error': {'code': 'VALIDATION_ERROR', 'message': 'Dữ liệu gửi lên không hợp lệ',
                      'details': [{'field': 'student_code', 'msg': 'Không có sinh viên với mã: SV404'}]},
          }),
        ('POST', '/admin/enrollments') => () {
            enrolled = [...enrolled, {'id': 9, 'full_name': 'Trần Gia Bảo', 'username': 'sv009',
                                      'student_code': 'SV009', 'face_status': 'none'}];
            return (201, {'class_id': 3, 'student_id': 9});
          }(),
        _ => (404, apiErr('NOT_FOUND', 'Không tìm thấy')),
      };
    });
    expect(find.text('IT4060 · Học kỳ 2026-1'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);          // phiên đã điểm danh
    expect(find.text('Nguyễn Văn An'), findsOneWidget);
    expect(find.text('TS. Trần Minh Đức (ducdm)'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'SV404');
    await t.tap(find.text('Thêm'));
    await t.pumpAndSettle();
    expect(find.text('Không có sinh viên với mã: SV404'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'SV009');
    await t.tap(find.text('Thêm'));
    await t.pumpAndSettle();
    expect(find.text('Trần Gia Bảo'), findsOneWidget);
    expect(http.calls.where((c) => c.startsWith('POST /admin/enrollments')).length, 2);
  });

  testWidgets('Nhập CSV: chạy thử báo lỗi theo dòng và chặn nút nhập; file đúng thì nhập và tải mật khẩu tạm', (t) async {
    var csv = 'role,username,full_name,student_code\nstudent,sv1,A,SV1\nteacher,sv2,B,\n';
    final downloads = <String, String>{};
    await _pump(
      t,
      (s) => ImportPage(
        session: s,
        pick: () async => PickedText('sv.csv', csv.length, csv),
        download: (name, text) => downloads[name] = text,
      ),
      (o) {
        final b = o.data as Map;
        if (b['csv_text'] == csv && csv.contains('teacher')) {
          return (200, {
            'ok': false, 'created': 0, 'passwords': [], 'total_rows': 2, 'error_rows': 1,
            'errors': [{'line': 3, 'col': 'role', 'msg': 'Vai trò không hợp lệ: teacher'}],
          });
        }
        return (200, {
          'ok': true, 'created': 1, 'total_rows': 1, 'error_rows': 0, 'errors': [],
          'passwords': b['dry_run'] == true ? [] : [{'username': 'sv1', 'temp_password': 'Ab3dEf7hJk'}],
        });
      },
    );
    await t.tap(find.widgetWithText(OutlinedButton, 'Chọn file'));
    await t.pumpAndSettle();
    expect(find.text('sv.csv'), findsOneWidget);
    expect(find.text('Chưa nhập dòng nào. Sửa 1 dòng lỗi rồi tải lại file.'), findsOneWidget);
    expect(find.text('Vai trò không hợp lệ: teacher'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Nhập 2 dòng')).onPressed, isNull);

    csv = 'role,username,full_name,student_code\nstudent,sv1,A,SV1\n';
    await t.tap(find.text('Chọn file khác'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Nhập 1 dòng'));
    await t.pumpAndSettle();
    expect(find.text('Đã nhập 1 dòng người dùng'), findsOneWidget);
    await t.tap(find.text('Tải file mật khẩu tạm'));
    expect(downloads['mat_khau_tam.csv'], 'username,temp_password\nsv1,Ab3dEf7hJk\n');
  });

  testWidgets('Nhật ký: gom theo ngày, câu mô tả có người, hành động, đối tượng', (t) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final http = await _pump(t, (s) => AuditPage(session: s), (o) => (200, page([
          {'id': 2, 'actor_name': 'Quản trị viên khoa', 'action': 'user.reset_password', 'target': 'users:7',
           'target_name': 'Nguyễn Văn An', 'before': null, 'after': null, 'created_at': now},
          {'id': 1, 'actor_name': 'Quản trị viên khoa', 'action': 'import.users', 'target': 'import',
           'target_name': null, 'before': null, 'after': {'created': 214}, 'created_at': now},
        ])));
    expect(find.textContaining('HÔM NAY'), findsOneWidget);
    expect(find.textContaining('đặt lại mật khẩu của'), findsOneWidget);
    expect(find.textContaining('Nguyễn Văn An'), findsOneWidget);
    expect(find.text('214 dòng'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'đức');
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(http.calls.length, 2);  // tải lần đầu + tải lại sau khi gõ tên người thực hiện
  });
}
