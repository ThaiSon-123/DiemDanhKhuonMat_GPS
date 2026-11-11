import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'files.dart';

/// Mở hộp chọn file của trình duyệt; null nếu người dùng hủy.
Future<PickedText?> pickTextFile({String accept = '.csv'}) {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept;
  final done = Completer<PickedText?>();
  input.onchange = (web.Event _) {
    final file = input.files?.item(0);
    if (file == null) {
      done.complete(null);
      return;
    }
    file.text().toDart.then((t) => done.complete(PickedText(file.name, file.size, t.toDart)),
        onError: done.completeError);
  }.toJS;
  input.oncancel = (web.Event _) {
    if (!done.isCompleted) done.complete(null);
  }.toJS;
  input.click();
  return done.future;
}

/// Tải chuỗi về máy dưới dạng file; thêm BOM để Excel đọc đúng tiếng Việt.
void downloadText(String fileName, String text) {
  final blob = web.Blob(['﻿$text'.toJS].toJS, web.BlobPropertyBag(type: 'text/csv;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..click();
  web.URL.revokeObjectURL(url);
}
