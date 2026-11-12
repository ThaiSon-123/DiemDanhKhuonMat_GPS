import 'dart:async';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/api_client.dart';
import '../../../core/api_error.dart';
import '../../../core/gps_sampler.dart';

enum CheckinStep { challenge, roomCode, gps, camera, submitting, result }

/// Lỗi khi xin thử thách / gửi lượt mà thử lại cũng vô ích: dừng hẳn, hiện thông điệp.
const finalCodes = {'ATTEMPTS_EXHAUSTED', 'ALREADY_PRESENT', 'SESSION_CLOSED', 'FACE_NOT_ENROLLED'};

/// Điều phối luồng điểm danh (đặc tả mục 4.4): thử thách → mã phòng (nếu bật) → GPS → camera → gửi → kết quả.
class CheckinController extends ChangeNotifier {
  CheckinController({
    required this.api,
    required this.sessionId,
    required this.gpsSource,
    required this.deviceId,
    DateTime Function()? now,
  }) : _now = now ?? clock.now;

  final ApiClient api;
  final int sessionId;
  final Stream<GpsSample> Function() gpsSource;
  final Future<String> Function() deviceId;
  final DateTime Function() _now;

  CheckinStep step = CheckinStep.challenge;
  bool busy = false;
  String? error; // lỗi tạm thời ở bước hiện tại (thử lại được)
  bool locationDenied = false;

  String? nonce;
  String? action;
  DateTime? expiresAt;
  int? attemptsLeft;
  bool roomCheck = false;
  String? roomToken;

  List<GpsSample>? samples;
  double? accuracy;
  int goodSamples = 0;

  String? result; // pass | suspicious | fail; null khi dừng vì finalCode
  String? recordStatus;
  String? reasonCode;
  String? reasonMessage;
  String? finalCode;
  DateTime? submittedAt;
  bool _autoRetried = false;

  static const studentMaxAcc = devGps ? 50000.0 : 30.0, studentMinGood = 3;

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  /// Giây còn lại của thử thách hiện tại.
  int get secondsLeft => expiresAt == null ? 0 : expiresAt!.difference(_now()).inSeconds.clamp(0, 999);

  Future<void> start() async {
    _set(() {
      step = CheckinStep.challenge;
      busy = true;
      error = null;
      result = reasonCode = reasonMessage = finalCode = null;
    });
    try {
      final c = await api.post('/sessions/$sessionId/challenge') as Map;
      nonce = '${c['nonce']}';
      action = '${c['action']}';
      expiresAt = DateTime.parse('${c['expires_at']}').toLocal();
      attemptsLeft = c['attempts_left'] as int;
      roomCheck = c['room_check'] == true;
      busy = false;
      if (roomCheck && roomToken == null) {
        _set(() => step = CheckinStep.roomCode);
      } else if (samples == null) {
        _set(() => step = CheckinStep.gps);
        unawaited(collectGps());
      } else {
        _set(() => step = CheckinStep.camera); // xin lại thử thách sau CHALLENGE_INVALID: giữ GPS, chụp lại mặt
      }
    } on ApiError catch (e) {
      _fail(e);
    }
  }

  void _fail(ApiError e) {
    if (finalCodes.contains(e.code)) {
      _set(() {
        busy = false;
        finalCode = e.code;
        reasonCode = e.code;
        reasonMessage = e.message;
        step = CheckinStep.result;
      });
    } else {
      _set(() {
        busy = false;
        error = e.message;
      });
    }
  }

  /// Nhận nội dung QR "dd:{session_id}:{mã}" hoặc mã gõ tay. Trả thông điệp lỗi, hoặc null nếu hợp lệ.
  String? submitRoomCode(String raw) {
    final text = raw.trim();
    String code;
    final parts = text.split(':');
    if (parts.length == 3 && parts[0] == 'dd') {
      if (parts[1] != '$sessionId') return 'Mã QR của phiên khác, hãy quét mã trên máy chiếu của lớp này';
      code = parts[2];
    } else {
      code = text.replaceAll(RegExp(r'\s'), '');
    }
    if (!RegExp(r'^[A-Za-z0-9]{8}$').hasMatch(code)) return 'Mã phòng gồm 8 ký tự, hãy quét lại'; // server kiểm tra chính xác
    _set(() {
      roomToken = code.toUpperCase();
      step = CheckinStep.gps;
    });
    unawaited(collectGps());
    return null;
  }

  Future<void> collectGps() async {
    _set(() {
      error = null;
      locationDenied = false;
      goodSamples = 0;
      accuracy = null;
    });
    final sampler = GpsSampler(gpsSource(),
        maxAcc: studentMaxAcc, minGood: studentMinGood, minDuration: const Duration(seconds: 5),
        timeout: const Duration(seconds: 15));
    final subs = [
      sampler.currentAccuracy.listen((a) => _set(() => accuracy = a)),
      sampler.goodCount.listen((g) => _set(() => goodSamples = g)),
    ];
    try {
      final s = await sampler.collect();
      if (checkExpired()) return;
      _set(() {
        samples = s;
        step = CheckinStep.camera;
      });
    } on GpsTimeout {
      _set(() => error = 'GPS chưa đủ chính xác. Bật Wi-Fi, đứng gần cửa sổ rồi thử lại.');
    } on LocationDenied catch (e) {
      _set(() {
        locationDenied = !e.serviceOff;
        error = e.serviceOff ? 'Định vị của máy đang tắt. Hãy bật Vị trí rồi thử lại.' : null;
      });
    } catch (e) {
      _set(() => error = 'Không lấy được vị trí: $e');
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
    }
  }

  /// Thử thách hết hạn trước khi gửi: quay về bước đầu (lượt mới sẽ được tính khi xin lại).
  bool checkExpired() {
    final live = {CheckinStep.roomCode, CheckinStep.gps, CheckinStep.camera};
    if (expiresAt == null || !live.contains(step) || _now().isBefore(expiresAt!)) return false;
    _set(() {
      step = CheckinStep.challenge;
      error = 'Hết thời gian thử thách. Bấm "Bắt đầu lại" để nhận thử thách mới.';
      nonce = null;
      roomToken = null; // mã phòng có thể đã đổi
      samples = null;
    });
    return true;
  }

  Future<void> submit(List<Uint8List> frames) async {
    if (checkExpired()) return;
    _set(() {
      step = CheckinStep.submitting;
      error = null;
    });
    try {
      await api.get('/me'); // làm mới token trước: FormData không gửi lại được nếu phải refresh giữa chừng
      final form = FormData.fromMap({
        'meta': '{"nonce":"$nonce","device_id":"${await deviceId()}",'
            '${roomToken == null ? '' : '"room_token":"$roomToken",'}'
            '"gps_samples":${_json(samples!)}}',
        'frames': [
          for (final (i, f) in frames.indexed)
            MultipartFile.fromBytes(f, filename: '$i.jpg', contentType: DioMediaType('image', 'jpeg')),
        ],
      });
      final r = await api.post('/sessions/$sessionId/checkin', data: form) as Map;
      final reason = r['reason'] as Map?;
      _set(() {
        result = '${r['result']}';
        recordStatus = '${r['record_status']}';
        attemptsLeft = r['attempts_left'] as int?;
        reasonCode = reason?['code'] as String?;
        reasonMessage = reason?['message'] as String?;
        submittedAt = _now();
        step = CheckinStep.result;
      });
    } on ApiError catch (e) {
      if (e.code == 'CHALLENGE_INVALID' && !_autoRetried) {
        _autoRetried = true;
        await start(); // xin thử thách mới một lần, giữ mẫu GPS, chụp lại mặt
        return;
      }
      if (finalCodes.contains(e.code) || e.code == 'CHALLENGE_INVALID') {
        _fail(ApiError(e.status, finalCodes.contains(e.code) ? e.code : 'SESSION_CLOSED', e.message));
      } else {
        _set(() {
          step = CheckinStep.camera;
          error = e.message;
        });
      }
    }
  }

  static String _json(List<GpsSample> s) =>
      '[${s.map((x) => '{"lat":${x.lat},"lng":${x.lng},"acc":${x.acc},"ts":${x.ts},"mock":${x.mock}}').join(',')}]';

  /// "Thử lại" sau một lượt không đạt: lượt mới, lấy lại vị trí và mặt.
  Future<void> retry() async {
    samples = null;
    roomToken = null;
    _autoRetried = false;
    await start();
  }
}
