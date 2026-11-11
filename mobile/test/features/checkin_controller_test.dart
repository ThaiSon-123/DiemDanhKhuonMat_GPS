import 'dart:async';
import 'dart:typed_data';

import 'package:diemdanh/core/gps_sampler.dart';
import 'package:diemdanh/features/student/checkin/checkin_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_http.dart';

Map<String, Object> ch({bool room = false, int left = 4}) => {
      'nonce': 'n${left}xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
      'action': 'turn_left',
      'expires_at': DateTime.now().add(const Duration(seconds: 60)).toUtc().toIso8601String(),
      'attempts_left': left,
      'room_check': room,
    };

Stream<GpsSample> goodGps() => Stream.fromIterable([for (var i = 0; i < 4; i++) GpsSample(21.0, 105.0, 10, i * 1000)]);

CheckinController make(Reply Function(RequestOptions) h, {DateTime Function()? now, FakeHttp? http}) =>
    CheckinController(
      api: fakeClient(http ?? FakeHttp(h)),
      sessionId: 41,
      gpsSource: goodGps,
      deviceId: () async => 'dev-1',
      now: now,
    );

final frames = List.generate(6, (i) => Uint8List.fromList([0xFF, 0xD8, i]));

/// Chờ GPS gom mẫu (minDuration 5 s) chạy xong trong fake async.
Future<void> settle() => Future<void>.delayed(const Duration(seconds: 6));

void main() {
  test('phiên không bật mã phòng thì bỏ qua bước mã phòng, GPS xong sang camera', () async {
    final c = make((o) => (200, ch()));
    await c.start();
    expect(c.step, CheckinStep.gps);
    await settle();
    expect(c.step, CheckinStep.camera);
    expect(c.samples, hasLength(4));
  });

  test('phiên bật mã phòng: kiểm tra QR đúng phiên, nhận cả mã gõ tay', () async {
    final c = make((o) => (200, ch(room: true)));
    await c.start();
    expect(c.step, CheckinStep.roomCode);
    expect(c.submitRoomCode('dd:99:K7Q2M9XA'), contains('phiên khác'));
    expect(c.submitRoomCode('abc'), contains('8 ký tự'));
    expect(c.submitRoomCode(' k7q2 m9xa '), isNull);
    expect(c.roomToken, 'K7Q2M9XA');
    expect(c.step, CheckinStep.gps);
  });

  test('lượt không đạt: hiện lý do của server và số lượt còn lại', () async {
    final c = make((o) => switch (o.path) {
          '/sessions/41/challenge' => (200, ch()),
          '/sessions/41/checkin' => (200, {
              'result': 'fail', 'record_status': 'absent', 'attempts_left': 3,
              'reason': {'code': 'ACTION_NOT_DETECTED', 'message': 'Chưa thấy bạn quay đầu sang trái'},
            }),
          _ => (200, {}),
        });
    await c.start();
    await settle();
    await c.submit(frames);
    expect(c.step, CheckinStep.result);
    expect((c.result, c.reasonMessage, c.attemptsLeft), ('fail', 'Chưa thấy bạn quay đầu sang trái', 3));
  });

  test('CHALLENGE_INVALID → tự xin thử thách mới đúng một lần, giữ GPS, quay lại camera', () async {
    var checkins = 0, challenges = 0;
    final c = make((o) {
      if (o.path.endsWith('/challenge')) {
        challenges++;
        return (200, ch(left: 4 - challenges));
      }
      if (o.path.endsWith('/checkin')) {
        checkins++;
        return (409, apiErr('CHALLENGE_INVALID', 'Thử thách không hợp lệ'));
      }
      return (200, {});
    });
    await c.start();
    await settle();
    await c.submit(frames);
    expect((challenges, c.step), (2, CheckinStep.camera));
    await c.submit(frames);  // lần hai vẫn sai: không tự xin nữa, dừng hẳn
    expect((challenges, checkins, c.step), (2, 2, CheckinStep.result));
    expect(c.finalCode, 'SESSION_CLOSED');
  });

  for (final code in ['ATTEMPTS_EXHAUSTED', 'ALREADY_PRESENT', 'SESSION_CLOSED', 'FACE_NOT_ENROLLED']) {
    test('$code khi xin thử thách: dừng hẳn với thông điệp của server', () async {
      final c = make((o) => (code == 'ATTEMPTS_EXHAUSTED' ? 429 : 409, apiErr(code, 'Thông điệp $code')));
      await c.start();
      expect((c.step, c.finalCode, c.reasonMessage), (CheckinStep.result, code, 'Thông điệp $code'));
    });
  }

  test('thử thách hết hạn trước khi gửi: quay về bước đầu, không gửi', () async {
    var now = DateTime.now();
    final http = FakeHttp((o) => (200, ch()));
    final c = make((_) => (200, {}), now: () => now, http: http);
    await c.start();
    await settle();
    now = now.add(const Duration(seconds: 61));
    await c.submit(frames);
    expect(c.step, CheckinStep.challenge);
    expect(c.error, contains('Hết thời gian'));
    expect(http.calls.where((x) => x.contains('/checkin')), isEmpty);
  });

  test('GPS không đủ chính xác: báo lỗi, ở lại bước GPS để thử lại', () async {
    final c = CheckinController(
      api: fakeClient(FakeHttp((o) => (200, ch()))),
      sessionId: 41,
      gpsSource: () => Stream.periodic(const Duration(seconds: 1), (i) => GpsSample(21, 105, 80, i * 1000)),
      deviceId: () async => 'dev-1',
    );
    await c.start();
    await Future<void>.delayed(const Duration(seconds: 16));
    expect(c.step, CheckinStep.gps);
    expect(c.error, contains('GPS chưa đủ chính xác'));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
