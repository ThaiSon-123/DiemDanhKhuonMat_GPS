import 'package:diemdanh/features/student/notices.dart';
import 'package:flutter_test/flutter_test.dart';

String iso(Duration d) => DateTime.now().add(d).toUtc().toIso8601String();

void main() {
  final classes = [
    {'id': 1, 'code': 'IT4060', 'name': 'Học máy', 'open_session': {'id': 41, 'expires_at': iso(const Duration(minutes: 5))}},
    {'id': 2, 'code': 'IT3100', 'name': 'CTDL', 'open_session': null},
  ];

  test('phiên đang mở và khuôn mặt bị từ chối là việc cần làm ngay; bỏ buổi cũ hơn 7 ngày', () {
    final n = buildNotices({'face': {'status': 'rejected', 'reject_reason': 'Ảnh mờ.'}}, classes, [
      {'session_id': 30, 'class_code': 'IT4060', 'opened_at': iso(const Duration(days: -1)), 'status': 'excused'},
      {'session_id': 20, 'class_code': 'IT4060', 'opened_at': iso(const Duration(days: -9)), 'status': 'rejected'},
    ]);
    expect(n.map((x) => x.title), ['IT4060 đang mở điểm danh', 'Ảnh khuôn mặt bị từ chối', 'Được ghi vắng có phép']);
    expect(n.where((x) => x.urgent).length, 2);
    expect(n.first.route, startsWith('/student/checkin/41'));
  });

  test('đã điểm danh ở phiên đang mở thì không nhắc nữa', () {
    final n = buildNotices({'face': {'status': 'approved'}}, classes, [
      {'session_id': 41, 'class_code': 'IT4060', 'opened_at': iso(Duration.zero), 'status': 'suspicious'},
    ]);
    expect(n.map((x) => x.title), ['Lượt điểm danh chờ duyệt']);
    expect(n.any((x) => x.urgent), isFalse);
  });
}
