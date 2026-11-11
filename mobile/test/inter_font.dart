import 'dart:io';

import 'package:flutter/services.dart';

/// Nạp font Inter thật cho widget test: font test mặc định vẽ mỗi ký tự thành ô vuông rộng
/// nên đo bố cục sai (báo tràn giả). Gọi trong setUpAll.
Future<void> loadInterFont() async {
  final loader = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Inter-$w.ttf').readAsBytesSync())));
  }
  await loader.load();
}
