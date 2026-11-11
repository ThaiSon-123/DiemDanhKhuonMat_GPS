import 'dart:async';

import 'package:clock/clock.dart';
import 'package:geolocator/geolocator.dart';

class GpsSample {
  const GpsSample(this.lat, this.lng, this.acc, this.ts, {this.mock = false});
  final double lat;
  final double lng;
  final double acc;
  final int ts; // mili giây; server chỉ dùng hiệu số giữa các mẫu
  final bool mock;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'acc': acc, 'ts': ts, 'mock': mock};
}

class GpsTimeout implements Exception {
  const GpsTimeout(this.good);
  final int good;
}

/// Người dùng từ chối quyền vị trí, hoặc tắt định vị của máy.
class LocationDenied implements Exception {
  const LocationDenied({this.serviceOff = false});
  final bool serviceOff;
}

/// Thu mẫu GPS (đặc tả mục 6.1): gửi **mọi** mẫu thô; xong khi đã qua [minDuration] và có ≥ [minGood] mẫu
/// có độ chính xác ≤ [maxAcc]. Quá [timeout] mà chưa đủ thì ném [GpsTimeout].
/// Sinh viên: 30 m, 3 mẫu, 5 s, 10 s. Giảng viên mở phiên: 20 m, 5 mẫu, 3 s, 20 s.
class GpsSampler {
  GpsSampler(this.source,
      {required this.maxAcc, required this.minGood, required this.minDuration, required this.timeout});
  final Stream<GpsSample> source;
  final double maxAcc;
  final int minGood;
  final Duration minDuration;
  final Duration timeout;

  final _acc = StreamController<double?>.broadcast();
  final _good = StreamController<int>.broadcast();

  /// Độ chính xác của mẫu mới nhất (để hiện "±18 m").
  Stream<double?> get currentAccuracy => _acc.stream;

  /// Số mẫu đạt đến hiện tại.
  Stream<int> get goodCount => _good.stream;

  Future<List<GpsSample>> collect() async {
    final samples = <GpsSample>[];
    final started = clock.now();
    final done = Completer<List<GpsSample>>();
    int good() => samples.where((s) => s.acc <= maxAcc).length;
    void check() {
      if (!done.isCompleted && good() >= minGood && clock.now().difference(started) >= minDuration) {
        done.complete(List.unmodifiable(samples));
      }
    }

    final sub = source.listen((s) {
      samples.add(s);
      _acc.add(s.acc);
      _good.add(good());
      check();
    }, onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
    });
    // Đủ mẫu sớm vẫn phải chờ hết minDuration: kiểm tra lại mỗi 250 ms.
    final tick = Timer.periodic(const Duration(milliseconds: 250), (_) => check());
    final limit = Timer(timeout, () {
      if (!done.isCompleted) done.completeError(GpsTimeout(good()));
    });
    try {
      return await done.future;
    } finally {
      tick.cancel();
      limit.cancel();
      unawaited(sub.cancel()); // không chờ: nguồn thật có thể đang đợi một lượt getCurrentPosition tới 8 s
    }
  }
}

/// Nguồn GPS thật: hỏi vị trí chính xác cao mỗi giây (chạy được trên Android, iOS, web).
Stream<GpsSample> deviceGps() async* {
  if (!await Geolocator.isLocationServiceEnabled()) throw const LocationDenied(serviceOff: true);
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw const LocationDenied();
  const settings = LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 8));
  while (true) {
    final p = await Geolocator.getCurrentPosition(locationSettings: settings);
    yield GpsSample(p.latitude, p.longitude, p.accuracy, DateTime.now().millisecondsSinceEpoch, mock: p.isMocked);
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }
}
