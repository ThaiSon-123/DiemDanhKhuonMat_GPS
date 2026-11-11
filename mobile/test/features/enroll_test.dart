import 'dart:typed_data';

import 'package:diemdanh/core/capture.dart';
import 'package:diemdanh/core/session.dart';
import 'package:diemdanh/features/faces/face_review_page.dart';
import 'package:diemdanh/features/student/consent_page.dart';
import 'package:diemdanh/features/student/enroll_page.dart';
import 'package:diemdanh/features/student/my_face_page.dart';
import 'package:diemdanh/features/student/student_home_page.dart';
import 'package:diemdanh/ui/theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../fake_http.dart';
import '../inter_font.dart';

class FakeCamera implements FaceCamera {
  FakeCamera({this.denied = false});
  final bool denied;
  int shots = 0;

  @override
  Future<void> init() async {
    if (denied) throw const CameraDenied();
  }

  @override
  Widget preview() => const ColoredBox(color: Colors.black);

  @override
  Future<Uint8List> capture() async => Uint8List.fromList([0xFF, 0xD8, shots++]);

  @override
  Future<void> dispose() async {}
}

Map<String, Object?> me({String face = 'none', bool consent = true, String? reason}) => {
      'id': 1, 'role': 'student', 'username': 'sv001', 'full_name': 'Nguyễn Văn An', 'student_code': 'SV001',
      'must_change_password': false,
      'consent': {'current_version': 'v1', 'accepted': consent},
      'face': {'status': face, 'reject_reason': reason, 'model_ok': face == 'approved' ? true : null, 'pending_update': false},
    };

/// Dựng trang trong một GoRouter tối thiểu; trả HTTP giả và danh sách đường dẫn đã chuyển tới.
Future<(FakeHttp, List<String>)> pump(WidgetTester t, Widget Function(Session) page, Reply Function(RequestOptions) h,
    {Size size = const Size(390, 844), bool settle = true}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final http = FakeHttp(h);
  final session = Session(fakeClient(http))..user = {'full_name': 'Nguyễn Văn An', 'username': 'sv001', 'role': 'student'};
  final went = <String>[];
  final router = GoRouter(initialLocation: '/p', routes: [
    GoRoute(path: '/p', builder: (_, _) => page(session)),
    GoRoute(path: '/:rest(.*)', builder: (_, s) {
      went.add(s.uri.path);
      return const Scaffold(body: Text('đã chuyển'));
    }),
  ]);
  await t.pumpWidget(MaterialApp.router(theme: appTheme(), routerConfig: router));
  if (settle) await t.pumpAndSettle();
  return (http, went);
}

void main() {
  setUpAll(loadInterFont);

  testWidgets('trang chủ hiện nút đăng ký khi face.status == none; chưa đồng ý thì sang màn đồng ý', (t) async {
    final (_, went) = await pump(t, (s) => StudentHomePage(session: s), (o) => switch (o.path) {
          '/me' => (200, me(consent: false)),
          '/me/classes' => (200, []),
          _ => (404, apiErr('NOT_FOUND', 'x')),
        });
    expect(find.text('Đăng ký khuôn mặt'), findsOneWidget);
    await t.tap(find.text('Đăng ký khuôn mặt'));
    await t.pumpAndSettle();
    expect(went, ['/student/consent']);
  });

  testWidgets('đồng ý dữ liệu: phải đánh dấu rồi mới bấm được, gửi đúng phiên bản', (t) async {
    final (http, went) = await pump(t, (s) => ConsentPage(session: s), (o) => switch (o.path) {
          '/me' => (200, me(consent: false)),
          '/me/consent' => (200, {'current_version': 'v1', 'accepted': true}),
          _ => (404, apiErr('NOT_FOUND', 'x')),
        });
    final btn = find.widgetWithText(FilledButton, 'Đồng ý và tiếp tục');
    expect(t.widget<FilledButton>(btn).onPressed, isNull);
    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(btn);
    await t.pumpAndSettle();
    expect(http.calls.where((c) => c.startsWith('POST /me/consent')).length, 1);
    expect(went, ['/student/enroll']);
  });

  testWidgets('đăng ký: hiện lý do từng ảnh từ ENROLL_REJECTED và chỉ chụp lại ảnh hỏng', (t) async {
    final cam = FakeCamera();
    final (http, _) = await pump(t, (s) => EnrollPage(session: s, camera: cam), (o) => switch (o.path) {
          '/me' => (200, me()),
          '/faces/enroll' => (422, {
              'error': {'code': 'ENROLL_REJECTED', 'message': 'Một số ảnh chưa đạt',
                        'details': {'photos': [{'index': 2, 'reason': 'BLURRY'}]}},
            }),
          _ => (404, apiErr('NOT_FOUND', 'x')),
        });
    for (var i = 1; i <= 3; i++) {
      await t.tap(find.text('Chụp ảnh $i'));
      await t.pumpAndSettle();
    }
    await t.tap(find.text('Gửi ảnh để duyệt'));
    await t.pumpAndSettle();
    expect(find.text('Ảnh 3: Ảnh bị mờ, hãy giữ máy chắc tay'), findsWidgets);
    expect(find.text('Chụp ảnh 3'), findsOneWidget);  // quay về đúng ảnh hỏng
    await t.tap(find.text('Chụp ảnh 3'));
    await t.pumpAndSettle();
    expect(cam.shots, 4);
    expect(find.text('Gửi ảnh để duyệt'), findsOneWidget);
    expect(http.calls.where((c) => c.startsWith('POST /faces/enroll')).length, 1);
  });

  testWidgets('từ chối quyền camera thì hiện màn hướng dẫn cấp quyền', (t) async {
    await pump(t, (s) => EnrollPage(session: s, camera: FakeCamera(denied: true)), (_) => (200, me()));
    expect(find.text('Cần quyền dùng camera'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
  });

  testWidgets('khuôn mặt của tôi: xóa phải xác nhận rồi mới gọi DELETE /me/face', (t) async {
    var face = 'rejected';
    final (http, _) = await pump(t, (s) => MyFacePage(session: s), (o) {
      if (o.method == 'DELETE') {
        face = 'none';
        return (204, '');
      }
      return (200, me(face: face, reason: 'Ảnh 2 ngược sáng'));
    });
    expect(find.text('Ảnh 2 ngược sáng'), findsOneWidget);
    await t.tap(find.text('Xóa dữ liệu khuôn mặt'));
    await t.pumpAndSettle();
    await t.tap(find.text('Hủy'));
    await t.pumpAndSettle();
    expect(http.calls.any((c) => c.startsWith('DELETE')), isFalse);
    await t.tap(find.text('Xóa dữ liệu khuôn mặt'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Xóa dữ liệu'));
    await t.pumpAndSettle();
    expect(http.calls.where((c) => c.startsWith('DELETE /me/face')).length, 1);
    expect(find.text('Chưa đăng ký'), findsOneWidget);
  });

  testWidgets('duyệt: từ chối phải có lý do; duyệt cần đánh dấu đối chiếu', (t) async {
    final (http, _) = await pump(t, (s) => Scaffold(body: FaceReviewPage(session: s)), size: const Size(1100, 1000), (o) => switch (o.path) {
          '/faces/pending' => (200, [
              {'id': 5, 'student_id': 7, 'full_name': 'Nguyễn Văn An', 'username': 'sv001', 'student_code': 'SV001',
               'created_at': DateTime.now().toUtc().toIso8601String(), 'is_update': false, 'classes': ['IT4060'],
               'photo_count': 1},
            ]),
          '/faces/5/photos' => (200, {'photos': ['data:image/jpeg;base64,/9j/']}),
          '/faces/5/review' => (200, {'id': 5, 'status': 'rejected'}),
          _ => (404, apiErr('NOT_FOUND', 'x')),
        });
    expect(find.text('Đăng ký lần đầu'), findsOneWidget);
    await t.tap(find.text('Từ chối'));
    await t.pumpAndSettle();
    expect(find.text('Từ chối phải ghi lý do để sinh viên chụp lại'), findsOneWidget);
    expect(http.calls.any((c) => c.contains('/review')), isFalse);
    final approve = find.widgetWithText(FilledButton, 'Duyệt khuôn mặt');
    expect(t.widget<FilledButton>(approve).onPressed, isNull);  // chưa đánh dấu đối chiếu

    await t.enterText(find.byType(TextField), 'Ảnh không khớp thẻ');
    await t.tap(find.text('Từ chối'));
    await t.pumpAndSettle();
    expect(http.calls.where((c) => c.startsWith('POST /faces/5/review')).length, 1);
  });
}
