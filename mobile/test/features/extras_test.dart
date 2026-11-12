import 'package:diemdanh/features/admin/banned_page.dart';
import 'package:diemdanh/features/lecturer/live_session_page.dart';
import 'package:diemdanh/features/lecturer/report_page.dart';
import 'package:diemdanh/features/schedule.dart';
import 'package:diemdanh/features/student/notices.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../inter_font.dart';
import 'enroll_test.dart' show pump;
import 'lecturer_test.dart' as l;

String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

void main() {
  setUpAll(loadInterFont);

  test('nhắc giờ: buổi hôm nay bắt đầu trong 30 phút tới; buổi đã qua hoặc còn xa thì không', () {
    final now = DateTime(2026, 11, 10, 6, 40); // Thứ Ba
    Map<String, dynamic> cls(String code, int weekday, String start, {Object? open}) => {
          'code': code, 'name': 'Lớp $code', 'open_session': open,
          'schedules': [{'weekday': weekday, 'start': start, 'end': '23:00', 'room': 'D9-301'}],
        };
    final classes = [cls('A', 2, '07:00'), cls('B', 2, '08:00'), cls('C', 2, '06:00'), cls('D', 3, '07:00')];
    expect(upcomingSlots(classes, now: now).map((s) => s.cls['code']), ['A']);
    expect(todaySlots(classes, now: now).map((s) => s.cls['code']), ['C', 'A', 'B']);
    final n = buildNotices({'face': {'status': 'approved'}}, classes, [], now: now);
    expect(n.single.title, 'Sắp đến giờ học A');
    expect(n.single.body, contains('07:00 · D9-301'));
    expect(scheduleSummary(classes.first), 'Thứ Ba 07:00–23:00 · D9-301');
  });

  testWidgets('điểm danh hàng loạt: chọn 2 người, đặt "Có mặt" kèm ghi chú', (t) async {
    late Map body;
    await l.pumpLong(t, (s) => LiveSessionPage(session: s, sessionId: 41), (o) {
      if (o.method == 'PATCH') {
        body = o.data as Map;
        return (200, {'updated': 2, 'skipped': 0});
      }
      return (200, l.records());
    });
    await t.tap(find.text('Điểm danh hàng loạt'));
    await t.pump();
    await t.tap(find.text('Tất cả'));
    await t.pump();
    expect(find.text('Chạm vào sinh viên để chọn'), findsOneWidget);
    await t.tap(find.text('Lê Thu Hà'));
    await t.tap(find.text('Hoàng Đức Minh'));
    await t.pump();
    expect(find.text('Đã chọn 2 sinh viên, đặt thành:'), findsOneWidget);
    expect([for (final c in t.widgetList<Checkbox>(find.byType(Checkbox))) c.value], [true, false, true]);
    await t.tap(find.widgetWithText(FilledButton, 'Có mặt'));
    await t.pump(const Duration(milliseconds: 300));
    await t.enterText(find.byType(TextField), 'Mất mạng');
    await t.tap(find.text('Xác nhận'));
    await t.pump(const Duration(milliseconds: 300));
    expect(body, {'student_ids': [12, 14], 'status': 'manual_present', 'note': 'Mất mạng'});
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('báo cáo: cột điểm chuyên cần và nhãn cấm thi', (t) async {
    await pump(t, (x) => ReportPage(session: x..user = {'role': 'lecturer'}, standalone: true), (o) => switch (o.path) {
          '/me/classes' => (200, [{'id': 3, 'code': 'IT4060', 'name': 'Học máy', 'semester': '2026-1'}]),
          _ => (200, {
              'class': {'id': 3, 'code': 'IT4060', 'name': 'Học máy', 'semester': '2026-1'}, 'session_count': 5,
              'first_try_pct': null, 'warn_absent': 3, 'sessions': [],
              'rows': [
                {'student_id': 1, 'student_code': 'SV001', 'full_name': 'Nguyễn Văn An', 'co_mat': 4, 'vang_co_phep': 1, 'vang': 0,
                  'chua_duyet': 0, 'so_buoi': 5, 'warn': false, 'diem': 10.0, 'cam_thi': false},
                {'student_id': 2, 'student_code': 'SV002', 'full_name': 'Lê Thu Hà', 'co_mat': 3, 'vang_co_phep': 0, 'vang': 2,
                  'chua_duyet': 0, 'so_buoi': 5, 'warn': false, 'diem': 6.0, 'cam_thi': true},
              ],
            }),
        }, size: const Size(1280, 900));
    expect(find.text('Điểm CC'), findsOneWidget);
    expect(find.text('10,0'), findsOneWidget);
    expect(find.text('6,0'), findsOneWidget);
    expect(find.text('Cấm thi'), findsOneWidget);
  });

  testWidgets('trang cấm thi: nhóm theo lớp, có nút xuất PDF/Excel', (t) async {
    await pump(t, (x) => Scaffold(body: BannedPage(session: x)), (o) => (200, {
          'semester': '2026-1', 'semesters': ['2026-1'], 'ban_absent_pct': 20,
          'rows': [
            {'class_code': 'IT4060', 'class_name': 'Học máy', 'student_code': 'SV002', 'full_name': 'Lê Thu Hà', 'vang': 2,
              'so_buoi': 5, 'pct': 40},
          ],
        }), size: const Size(1280, 800));
    expect(find.text('Không đủ điều kiện dự thi'), findsOneWidget);
    expect(find.text('IT4060 · Học máy'), findsOneWidget);
    expect(find.text('Vắng 2/5 buổi'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('PDF nộp phòng đào tạo'), findsOneWidget);
  });
}
