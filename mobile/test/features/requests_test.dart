import 'package:diemdanh/features/admin/overview_page.dart';
import 'package:diemdanh/features/lecturer/requests_page.dart';
import 'package:diemdanh/features/student/history_page.dart';
import 'package:diemdanh/features/student/request_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../inter_font.dart';
import 'enroll_test.dart' show pump;

String iso(Duration d) => DateTime.now().add(d).toUtc().toIso8601String();

Map<String, Object?> req({int id = 5, String kind = 'leave', String status = 'pending', bool file = true}) => {
      'id': id, 'kind': kind, 'session_id': 41, 'reason': 'Em bị sốt, có giấy khám', 'status': status,
      'decision_note': status == 'rejected' ? 'Thiếu giấy' : null, 'created_at': iso(Duration.zero),
      'decided_at': status == 'pending' ? null : iso(Duration.zero), 'has_attachment': file,
      'opened_at': iso(const Duration(days: -2)), 'class_id': 3, 'class_code': 'IT4060', 'class_name': 'Học máy',
      'student_id': 12, 'full_name': 'Lê Thu Hà', 'student_code': 'SV014', 'record_status': 'absent',
    };

void main() {
  setUpAll(loadInterFont);

  test('chỉ gửi đơn cho buổi đã đóng, đang vắng / bị từ chối, trong 14 ngày, chưa có đơn chờ', () {
    Map<String, dynamic> row(String status, {int days = 2, bool open = false}) =>
        {'status': status, 'is_open': open, 'opened_at': iso(Duration(days: -days))};
    expect(canRequest(row('absent'), null), isTrue);
    expect(canRequest(row('rejected'), {'status': 'rejected'}), isTrue);
    expect(canRequest(row('absent', open: true), null), isFalse);
    expect(canRequest(row('present'), null), isFalse);
    expect(canRequest(row('absent', days: 20), null), isFalse);
    expect(canRequest(row('absent'), {'status': 'pending'}), isFalse);
  });

  testWidgets('giảng viên duyệt đơn; từ chối bắt buộc ghi lý do', (t) async {
    final decided = <Map>[];
    await pump(t, (s) => LecturerRequestsPage(session: s), (o) {
      if (o.path.endsWith('/decide')) {
        decided.add(o.data as Map);
        return (200, {});
      }
      return (200, [req(), req(id: 6, kind: 'appeal', file: false), req(id: 7, status: 'approved')]);
    });
    expect(find.text('Chờ duyệt · 2'), findsOneWidget);
    expect(find.text('Xin nghỉ'), findsOneWidget);
    expect(find.text('Khiếu nại'), findsOneWidget);
    expect(find.text('Xem giấy tờ'), findsOneWidget);

    await t.tap(find.text('Duyệt').first);
    await t.pumpAndSettle();
    expect(find.textContaining('Vắng có phép'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Duyệt').last);
    await t.pumpAndSettle();
    expect(decided.last, {'decision': 'approve', 'note': null});

    await t.tap(find.text('Từ chối').last);
    await t.pumpAndSettle();
    FilledButton confirm() => t.widget(find.widgetWithText(FilledButton, 'Từ chối'));
    expect(confirm().onPressed, isNull);
    await t.enterText(find.byType(TextField), 'Không có minh chứng');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Từ chối'));
    await t.pumpAndSettle();
    expect(decided.last, {'decision': 'reject', 'note': 'Không có minh chứng'});
  });

  testWidgets('lịch sử: cảnh báo vắng nhiều, gửi đơn cho buổi vắng, hiện trạng thái đơn', (t) async {
    final sent = <String>[];
    await pump(t, (s) => StudentHistoryPage(session: s), (o) => switch (o.path) {
          '/me/attendance' => (200, [
              {'session_id': 41, 'class_id': 3, 'class_code': 'IT4060', 'class_name': 'Học máy', 'opened_at': iso(const Duration(days: -2)),
                'status': 'absent', 'checked_at': null, 'is_open': false},
              {'session_id': 40, 'class_id': 3, 'class_code': 'IT4060', 'class_name': 'Học máy', 'opened_at': iso(const Duration(days: -9)),
                'status': 'absent', 'checked_at': null, 'is_open': false},
            ]),
          '/me/requests' when o.method == 'POST' => () {
              sent.add(o.data.runtimeType.toString());
              return (201, req());
            }(),
          '/me/requests' => (200, [req(status: 'rejected')..['session_id'] = 40]),
          '/me/classes' => (200, [{'id': 3, 'code': 'IT4060', 'name': 'Học máy', 'absences': 3, 'warn': true, 'warn_absent': 3}]),
          _ => (404, {}),
        });
    expect(find.textContaining('Bạn đã vắng 3 buổi'), findsOneWidget);
    expect(find.text('Đơn xin nghỉ bị từ chối: Thiếu giấy'), findsOneWidget);
    expect(find.text('Gửi đơn khác'), findsOneWidget);
    await t.tap(find.text('Xin nghỉ / khiếu nại'));
    await t.pumpAndSettle();
    expect(find.text('Gửi đơn cho giảng viên'), findsOneWidget);
    await t.tap(find.text('Gửi đơn'));
    await t.pump();
    expect(find.textContaining('ít nhất 5 ký tự'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Em bị sốt cao');
    await t.tap(find.text('Gửi đơn'));
    await t.pumpAndSettle();
    expect(sent, ['FormData']);
    expect(find.textContaining('Đã gửi đơn'), findsOneWidget);
  });

  testWidgets('tổng quan quản trị: KPI, lớp theo tỉ lệ, cờ đáng ngờ', (t) async {
    await pump(t, (s) => Scaffold(body: OverviewPage(session: s)), (o) => (200, {
          'semesters': ['2026-1'], 'semester': '2026-1', 'warn_absent': 3,
          'totals': {'classes': 2, 'sessions': 12, 'present_pct': 88, 'warn_students': 4, 'attempts': 100, 'pass': 84,
            'suspicious': 9, 'pending_requests': 2},
          'classes': [
            {'id': 1, 'code': 'IT4060', 'name': 'Học máy', 'lecturer_name': 'TS. Trần Minh Đức', 'students': 62, 'sessions': 10,
              'records': 600, 'present': 560, 'suspicious': 3, 'excused': 5, 'warn_students': 1, 'present_pct': 93},
            {'id': 2, 'code': 'IT3100', 'name': 'CTDL', 'lecturer_name': 'ThS. Lê Hà', 'students': 40, 'sessions': 2,
              'records': 80, 'present': 52, 'suspicious': 0, 'excused': 0, 'warn_students': 3, 'present_pct': 65},
          ],
          'flags': [{'flag': 'LOCATION_DRIFT', 'n': 7}, {'flag': 'FACE_BORDERLINE', 'n': 2}],
          'fail_reasons': [{'reason': 'GPS_TOO_FAR', 'n': 5}],
        }), size: const Size(1280, 1000));
    expect(find.text('Tổng quan'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);
    expect(find.text('84%'), findsOneWidget);
    expect(find.text('Lệch vị trí'), findsOneWidget);
    expect(find.text('Ở xa lớp'), findsOneWidget);
    // Lớp tỉ lệ thấp đứng trước
    expect(t.getTopLeft(find.text('CTDL')).dy, lessThan(t.getTopLeft(find.text('Học máy')).dy));
  });
}
