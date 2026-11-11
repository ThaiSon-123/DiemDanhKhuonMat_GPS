import 'dart:async';

import 'package:diemdanh/core/gps_sampler.dart';
import 'package:flutter_test/flutter_test.dart';

GpsSample s(double acc, int i) => GpsSample(21.0, 105.0, acc, i * 1000);

void main() {
  test('trả mọi mẫu thô khi đủ mẫu đạt và đã qua minDuration', () async {
    final src = StreamController<GpsSample>();
    final sampler = GpsSampler(src.stream,
        maxAcc: 30, minGood: 3, minDuration: const Duration(milliseconds: 300), timeout: const Duration(seconds: 3));
    final accs = <double?>[];
    sampler.currentAccuracy.listen(accs.add);
    final f = sampler.collect();
    for (final (i, acc) in [40.0, 12.0, 50.0, 10.0, 9.0].indexed) {
      src.add(s(acc, i));
      await Future<void>.delayed(Duration.zero);
    }
    final out = await f;
    expect(out.map((e) => e.acc), [40.0, 12.0, 50.0, 10.0, 9.0]);  // gửi cả mẫu kém: server tự lọc
    expect(accs.last, 9.0);
  });

  test('đủ mẫu sớm vẫn chờ hết minDuration', () async {
    final src = StreamController<GpsSample>();
    final sampler = GpsSampler(src.stream,
        maxAcc: 30, minGood: 1, minDuration: const Duration(milliseconds: 400), timeout: const Duration(seconds: 3));
    final sw = Stopwatch()..start();
    final f = sampler.collect();
    src.add(s(5, 0));
    await f;
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(380));
  });

  test('ném GpsTimeout khi không đủ mẫu đạt', () async {
    final src = StreamController<GpsSample>();
    final sampler = GpsSampler(src.stream,
        maxAcc: 30, minGood: 3, minDuration: Duration.zero, timeout: const Duration(milliseconds: 200));
    final f = sampler.collect();
    src.add(s(10, 0));
    src.add(s(45, 1));
    await expectLater(f, throwsA(isA<GpsTimeout>().having((e) => e.good, 'good', 1)));
  });

  test('lỗi của nguồn (vd từ chối quyền) được chuyển ra ngoài', () async {
    final sampler = GpsSampler(Stream.error(const LocationDenied()),
        maxAcc: 30, minGood: 3, minDuration: Duration.zero, timeout: const Duration(seconds: 1));
    await expectLater(sampler.collect(), throwsA(isA<LocationDenied>()));
  });
}
