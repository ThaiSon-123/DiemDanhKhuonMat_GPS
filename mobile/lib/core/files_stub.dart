import 'dart:typed_data';

import 'files.dart';

Future<PickedText?> pickTextFile({String accept = '.csv'}) =>
    throw UnsupportedError('Chọn file chỉ dùng trên trang quản trị web');

void downloadText(String fileName, String text) =>
    throw UnsupportedError('Tải file chỉ dùng trên trang quản trị web');

void downloadBytes(String fileName, Uint8List bytes, String mime) =>
    throw UnsupportedError('Tải file chỉ dùng trên bản web');
