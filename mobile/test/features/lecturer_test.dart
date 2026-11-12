import 'package:diemdanh/core/gps_sampler.dart';
import 'package:diemdanh/core/session.dart';
import 'package:diemdanh/features/lecturer/live_session_page.dart';
import 'package:diemdanh/features/lecturer/open_session_page.dart';
import 'package:diemdanh/features/lecturer/report_page.dart';
import 'package:diemdanh/features/lecturer/room_code_page.dart';
import 'package:diemdanh/features/lecturer/session_history_page.dart';
import 'package:diemdanh/features/lecturer/student_detail_page.dart';
import 'package:diemdanh/features/student/history_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_http.dart';
import '../inter_font.dart';
import 'enroll_test.dart' show pump;

String iso(Duration d) => DateTime.now().add(d).toUtc().toIso8601String();

Map<String, Object?> attempt({String result = 'suspicious', List<String> flags = const ['LOCATION_DRIFT'], double d = 56}) => {
      'id': 901, 'result': result, 'received_at': iso(Duration.zero), 'face_score': 0.71, 'distance_m': d, 'radius_m': 47.0,
      'accuracy_m': 19.0, 'flags': flags, 'fail_step': null, 'fail_reason': null, 'room_token_ok': null,
      'liveness_score': 0.97, 'action_ok': true, 'has_evidence': true,
    };

Map<String, Object?> records({bool open = true, bool recenter = false}) => {
      'session': {
        'id': 41, 'class_id': 3, 'class': {'id': 3, 'code': 'IT4060', 'name': 'Học máy', 'semester': '2026-1'},
        'opened_at': iso(const Duration(minutes: -4)), 'expires_at': iso(const Duration(minutes: 6)), 'closed_at': null,
        'is_open': open, 'room_check': true, 'base_radius_m': 20.0, 'center': {'lat': 21.0, 'lng': 105.8},
        'recentered': false, 'recenter_suggested': recenter,
      },
      'counts': {'absent': 1, 'suspicious': 1, 'present': 1, 'manual_present': 0, 'excused': 0, 'rejected': 0},
      'records': [
        {'student_id': 12, 'student_code': 'SV014', 'full_name': 'Lê Thu Hà', 'status': 'suspicious', 'decided_by': null,
          'note': null, 'attempt_count': 2, 'last_attempt': attempt()},
        {'student_id': 13, 'student_code': 'SV015', 'full_name': 'Trần Gia Bảo', 'status': 'present', 'decided_by': null,
          'note': null, 'attempt_count': 1, 'last_attempt': attempt(result: 'pass', flags: [], d: 5)},
        {'student_id': 14, 'student_code': 'SV016', 'full_name': 'Hoàng Đức Minh', 'status': 'absent', 'decided_by': null,
          'note': null, 'attempt_count': 0, 'last_attempt': null},
      ],
    };

void main() {
  setUpAll(loadInterFont);

  testWidgets('mở phiên: nút tắt đến khi đủ 5 mẫu ≤ 20 m, rồi gửi mọi mẫu và sang phiên đang chạy', (t) async {
    Stream<GpsSample> gps() => Stream.periodic(const Duration(milliseconds: 500), (i) => GpsSample(21, 105.8, i < 2 ? 35 : 9, i * 500));
    late Map body;
    final (http, went) = await pumpLong(t, (s) => OpenSessionPage(session: s, classId: 3, classCode: 'IT4060', gpsSource: gps),
        (o) {
      body = o.data as Map;
      return (201, {'session_id': 41});
    });
    FilledButton btn() => t.widget(find.widgetWithText(FilledButton, 'Mở phiên điểm danh'));
    await t.pump(const Duration(seconds: 2));
    expect(btn().onPressed, isNull);
    expect(find.textContaining('Cần thêm'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(milliseconds: 300));
    expect(btn().onPressed, isNotNull);
    await t.tap(find.text('15 phút'));
    await t.tap(find.widgetWithText(FilledButton, 'Mở phiên điểm danh'));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect((body['class_id'], body['duration_min'], body['room_check']), (3, 15, true));
    expect((body['gps_samples'] as List).length, greaterThanOrEqualTo(7)); // gửi cả mẫu kém
    expect(went, ['/lecturer/session/41']);
    expect(http.calls.single, startsWith('POST /sessions'));
  });

  testWidgets('phiên đang chạy: bộ đếm, lọc đáng ngờ, hỏi lại mỗi 4 s, dừng khi rời trang', (t) async {
    final (http, _) = await pumpLong(t, (s) => LiveSessionPage(session: s, sessionId: 41), (o) => (200, records()));
    expect(find.text('Học máy'), findsOneWidget);
    expect(find.text('Lê Thu Hà'), findsOneWidget); // mặc định lọc "Đáng ngờ"
    expect(find.text('Trần Gia Bảo'), findsNothing);
    expect(find.text('Lệch vị trí 56 m'), findsOneWidget);
    await t.tap(find.text('Tất cả'));
    await t.pump();
    expect(find.text('Trần Gia Bảo'), findsOneWidget);
    final before = http.calls.length;
    await t.pump(const Duration(seconds: 4));
    await t.pump(const Duration(milliseconds: 50));
    expect(http.calls.length, before + 1);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
    expect(http.calls.length, before + 1);
  });

  testWidgets('dải tâm lệch hiện khi recenter_suggested, bấm thì gọi recenter', (t) async {
    final (http, _) = await pumpLong(t, (s) => LiveSessionPage(session: s, sessionId: 41),
        (o) => o.path.endsWith('/recenter') ? (200, {'center': {}, 're_evaluated': 3}) : (200, records(recenter: true)));
    expect(find.textContaining('Tâm phiên có thể lệch'), findsOneWidget);
    await t.tap(find.text('Tính lại tâm'));
    await t.pump(const Duration(milliseconds: 100));
    expect(http.calls.where((c) => c.startsWith('POST /sessions/41/recenter')), hasLength(1));
  });

  testWidgets('đóng phiên hỏi xác nhận rồi gọi close', (t) async {
    final (http, _) = await pumpLong(t, (s) => LiveSessionPage(session: s, sessionId: 41), (o) => (200, records()));
    await t.tap(find.text('Đóng'));
    await t.pump();
    expect(find.text('Đóng phiên điểm danh?'), findsOneWidget);
    await t.tap(find.text('Đóng phiên'));
    await t.pump(const Duration(milliseconds: 100));
    expect(http.calls.where((c) => c.startsWith('POST /sessions/41/close')), hasLength(1));
  });

  testWidgets('chi tiết sinh viên: hiện d, r; lưu quyết định kèm ghi chú bằng PATCH', (t) async {
    late Map patched;
    await pump(t, (s) => StudentDetailPage(session: s, sessionId: 41, studentId: 12), (o) {
      if (o.method == 'PATCH') {
        patched = o.data as Map;
        return (200, {});
      }
      return (200, {
        'session': {'id': 41, 'is_open': true},
        'record': {'student_id': 12, 'student_code': 'SV014', 'full_name': 'Lê Thu Hà', 'status': 'suspicious',
          'decided_by': null, 'note': null, 'updated_at': iso(Duration.zero)},
        'attempts': [attempt(), attempt(result: 'fail', flags: [])..['fail_reason'] = 'GPS_TOO_FAR'],
      });
    });
    expect(find.text('Lê Thu Hà'), findsOneWidget);
    expect(find.text('d = 56 m'), findsOneWidget);
    expect(find.text('r = 47 m'), findsOneWidget);
    FilledButton save() => t.widget(find.widgetWithText(FilledButton, 'Lưu quyết định'));
    expect(save().onPressed, isNull);
    await t.tap(find.text('Có mặt').last);
    await t.enterText(find.byType(TextField), 'Đã thấy SV ngồi bàn cuối');
    await t.pump();
    await t.ensureVisible(find.text('Lưu quyết định'));
    await t.tap(find.text('Lưu quyết định'));
    await t.pumpAndSettle();
    expect(patched, {'status': 'manual_present', 'note': 'Đã thấy SV ngồi bàn cuối'});
  });

  testWidgets('chiếu mã phòng: hiện mã, lấy mã mới khi hết cửa sổ', (t) async {
    var n = 0;
    final (http, _) = await pumpLong(t, (s) => RoomCodePage(session: s, sessionId: 41), (o) {
      if (o.path.endsWith('/room-token')) {
        n++;
        return (200, {'code': n == 1 ? 'K7Q2M9XA' : 'ABCD1234', 'window_ends_at': iso(const Duration(seconds: 3)),
          'qr_payload': 'dd:41:K7Q2M9XA'});
      }
      return (200, records());
    }, size: const Size(1280, 800));
    expect(find.text('K7Q2 M9XA'), findsOneWidget);
    expect(find.text('Học máy'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('ABCD 1234'), findsOneWidget);
    expect(http.calls.where((c) => c.contains('/room-token')).length, 2);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('lịch sử phiên: số buổi, tỉ lệ TB, chờ duyệt', (t) async {
    Map<String, Object?> s(int id, int present, int sus) => {
          'id': id, 'opened_at': iso(Duration(days: -id)), 'expires_at': iso(Duration(days: -id, minutes: 10)),
          'closed_at': null, 'is_open': false, 'room_check': false, 'base_radius_m': 20.0,
          'counts': {'present': present, 'suspicious': sus, 'absent': 10 - present - sus, 'excused': 0, 'rejected': 0, 'total': 10},
        };
    await pump(t, (x) => SessionHistoryPage(session: x, classId: 3, classCode: 'IT4060', studentCount: 10),
        (o) => (200, [s(1, 9, 1), s(2, 7, 0)]));
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('1 lượt chờ duyệt'), findsOneWidget);
    expect(find.text('9/10 có mặt'), findsOneWidget);
  });

  testWidgets('báo cáo: KPI, bảng sinh viên; vắng ≥ 3 buổi được đếm', (t) async {
    await pump(t, (x) => ReportPage(session: x..user = {'role': 'lecturer'}, standalone: true), (o) => switch (o.path) {
          '/me/classes' => (200, [{'id': 3, 'code': 'IT4060', 'name': 'Học máy', 'semester': '2026-1'}]),
          _ => (200, {
              'class': {'id': 3, 'code': 'IT4060', 'name': 'Học máy', 'semester': '2026-1'}, 'session_count': 4,
              'first_try_pct': 84, 'warn_absent': 3,
              'sessions': [for (var i = 0; i < 4; i++) {'id': i, 'opened_at': iso(Duration(days: -i)), 'present': 2, 'suspicious': 0, 'total': 2}],
              'rows': [
                {'student_id': 1, 'student_code': 'SV001', 'full_name': 'Nguyễn Văn An', 'co_mat': 4, 'vang_co_phep': 0, 'vang': 0, 'chua_duyet': 0, 'so_buoi': 4},
                {'student_id': 2, 'student_code': 'SV022', 'full_name': 'Hoàng Đức Minh', 'co_mat': 1, 'vang_co_phep': 0, 'vang': 3, 'chua_duyet': 0, 'so_buoi': 4, 'warn': true},
              ],
            }),
        }, size: const Size(1280, 980));
    expect(find.text('Báo cáo chuyên cần · Học máy'), findsOneWidget);
    expect(find.text('1 SV'), findsOneWidget);
    expect(find.text('84%'), findsOneWidget);
    expect(find.text('Hoàng Đức Minh'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    // Xuất Excel gọi đúng định dạng; trong test (không phải web) báo chỉ tải được trên bản web.
    expect(find.text('PDF nộp khoa'), findsOneWidget);
    expect(find.text('CSV'), findsOneWidget);
    await t.tap(find.text('Xuất Excel'));
    await t.pumpAndSettle();
    expect(find.text('Xuất file dùng trên bản web (laptop).'), findsOneWidget);
  });

  testWidgets('lịch sử chuyên cần sinh viên: theo lớp, tỉ lệ, nhãn trạng thái', (t) async {
    Map<String, Object?> r(int day, String code, String status, {bool checked = true}) => {
          'session_id': day, 'class_id': 1, 'class_code': code, 'class_name': code == 'IT4060' ? 'Học máy' : 'CTDL',
          'opened_at': iso(Duration(days: -day)), 'status': status, 'checked_at': checked ? iso(Duration(days: -day)) : null,
        };
    await pump(t, (x) => StudentHistoryPage(session: x), (o) => (200, [
          r(1, 'IT4060', 'suspicious'), r(2, 'IT4060', 'present'), r(3, 'IT4060', 'absent', checked: false),
          r(4, 'IT4060', 'excused', checked: false), r(5, 'IT3100', 'present'),
        ]));
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('Chờ duyệt'), findsOneWidget);
    expect(find.text('Không điểm danh'), findsOneWidget);
    expect(find.text('Buổi 4'), findsOneWidget);
    await t.tap(find.text('IT3100'));
    await t.pump();
    expect(find.text('100%'), findsOneWidget);
  });
}

/// Như [pump] nhưng không chờ "settle" (trang có hẹn giờ / vòng tải chạy mãi): đẩy thời gian giả vài nhịp.
Future<(FakeHttp, List<String>)> pumpLong(WidgetTester t, Widget Function(Session) page, Reply Function(RequestOptions) h,
    {Size size = const Size(390, 844)}) async {
  final r = await pump(t, page, h, size: size, settle: false);
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
  return r;
}
