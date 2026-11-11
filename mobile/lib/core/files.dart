/// Chọn file văn bản và tải file về. Chỉ chạy trên Flutter Web (trang quản trị); nền tảng khác báo không hỗ trợ.
library;

export 'files_stub.dart' if (dart.library.js_interop) 'files_web.dart';

class PickedText {
  const PickedText(this.name, this.size, this.text);
  final String name;
  final int size;
  final String text;
}
