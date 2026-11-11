import 'dart:async';

import 'package:diemdanh/core/gps_sampler.dart';
import 'package:diemdanh/core/session.dart';
import 'package:diemdanh/features/student/checkin/checkin_page.dart';
import 'package:diemdanh/features/student/permissions_page.dart';
import 'package:diemdanh/ui/theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../fake_http.dart';
import '../inter_font.dart';
import 'enroll_test.dart' show FakeCamera;

Map<String, Object> ch({bool room = false}) => {
      'nonce': 'nxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
      'action': 'turn_left',
      'expires_at': DateTime.now().add(const Duration(seconds: 90)).toUtc().toIso8601String(),
      'attempts_left': 4,
      'room_check': room,
    };

Stream<GpsSample> goodGps() => Stream.periodic(const Duration(seconds: 1), (i) => GpsSample(21, 105, 12, i * 1000));

Future<FakeHttp> pumpCheckin(WidgetTester t, Reply Function(RequestOptions) h,
    {Stream<GpsSample> Function()? gps, Widget Function(ValueChanged<String>)? scanner}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final http = FakeHttp(h);
  final session = Session(fakeClient(http));
  final router = GoRouter(initialLocation: '/p', routes: [
    GoRoute(path: '/p', builder: (_, _) => CheckinPage(
          session: session, sessionId: 41, classCode: 'INT3306', className: 'Phát triển ứng dụng Web',
          camera: FakeCamera(), gpsSource: gps ?? goodGps, deviceId: () async => 'dev-1',
          scanner: scanner ?? (_) => const ColoredBox(color: Colors.black))),
    GoRoute(path: '/:rest(.*)', builder: (_, _) => const Scaffold(body: Text('đã chuyển'))),
  ]);
  await t.pumpWidget(MaterialApp.router(theme: appTheme(), routerConfig: router));
  await settle(t);
  return http;
}

/// Đẩy thời gian giả của widget test (HTTP giả, GPS, hẹn giờ chụp đều chạy theo nó).
Future<void> settle(WidgetTester t, [Duration d = const Duration(milliseconds: 100)]) async {
  for (var left = d; left > Duration.zero; left -= const Duration(milliseconds: 100)) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// GPS cần ≥ 3 mẫu và ≥ 5 giây.
Future<void> passGps(WidgetTester t) => settle(t, const Duration(milliseconds: 6200));

Reply checkinReply(RequestOptions o, Map<String, Object?> result) => switch (o.path) {
      '/sessions/41/challenge' => (200, ch()),
      '/sessions/41/checkin' => (200, result),
      '/me' => (200, {}),
      _ => (404, apiErr('NOT_FOUND', 'x')),
    };

Future<void> captureAll(WidgetTester t) async {
  await t.tap(find.text('Bắt đầu'));
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
  await settle(t);
}

void main() {
  setUpAll(loadInterFont);

  testWidgets('GPS → camera → đạt: hiện "Đã điểm danh", gửi 6 khung', (t) async {
    final http = await pumpCheckin(t, (o) => checkinReply(o, {'result': 'pass', 'record_status': 'present', 'attempts_left': 3}));
    expect(find.text('Đang lấy mẫu vị trí'), findsOneWidget);
    await settle(t, const Duration(milliseconds: 1200));
    expect(find.text('±12 m'), findsOneWidget);
    await passGps(t);
    expect(find.text('Quay đầu sang trái'), findsOneWidget);
    expect(find.text('0/6'), findsOneWidget);
    await captureAll(t);
    expect(find.text('Đã điểm danh'), findsOneWidget);
    expect(http.calls.where((c) => c.contains('/checkin')), hasLength(1));
    await t.tap(find.text('Về trang chủ'));
    await t.pumpAndSettle();
    expect(find.text('đã chuyển'), findsOneWidget);
  });

  testWidgets('không đạt: hiện lý do, lượt còn lại và nút Thử lại', (t) async {
    await pumpCheckin(t, (o) => checkinReply(o, {
          'result': 'fail', 'record_status': 'absent', 'attempts_left': 3,
          'reason': {'code': 'ACTION_NOT_DETECTED', 'message': 'Chưa thấy bạn quay đầu sang trái'},
        }));
    await passGps(t);
    await captureAll(t);
    expect(find.text('Chưa điểm danh được'), findsOneWidget);
    expect(find.text('Chưa thấy bạn quay đầu sang trái'), findsOneWidget);
    expect(find.text('3/5'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
  });

  testWidgets('chờ giảng viên khi kết quả nghi ngờ', (t) async {
    await pumpCheckin(t, (o) => checkinReply(o, {'result': 'suspicious', 'record_status': 'pending', 'attempts_left': 3}));
    await passGps(t);
    await captureAll(t);
    expect(find.text('Đang chờ giảng viên'), findsOneWidget);
    expect(find.text('Thử lại'), findsNothing);
  });

  testWidgets('phiên bật mã phòng: mã sai báo lỗi, mã đúng sang bước vị trí', (t) async {
    late ValueChanged<String> scan;
    await pumpCheckin(t, (o) => (200, ch(room: true)), scanner: (on) {
      scan = on;
      return const ColoredBox(color: Colors.black);
    });
    expect(find.text('Quét mã QR trên máy chiếu'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'abc');
    await t.tap(find.text('Xác nhận'));
    await t.pump();
    expect(find.textContaining('8 ký tự'), findsOneWidget);
    scan('dd:41:K7Q2M9XA');
    await settle(t);
    expect(find.text('Đang lấy mẫu vị trí'), findsOneWidget);
    await passGps(t);
  });

  testWidgets('từ chối quyền vị trí: hiện màn cấp quyền', (t) async {
    await pumpCheckin(t, (o) => (200, ch()), gps: () async* {
      throw const LocationDenied();
    });
    await settle(t);
    expect(find.byType(PermissionsPage), findsOneWidget);
  });

  testWidgets('đã điểm danh rồi: dừng, không cho thử lại', (t) async {
    await pumpCheckin(t, (o) => (409, apiErr('ALREADY_PRESENT', 'Bạn đã điểm danh rồi')));
    expect(find.text('Đã điểm danh'), findsOneWidget);
    expect(find.text('Thử lại'), findsNothing);
  });
}
