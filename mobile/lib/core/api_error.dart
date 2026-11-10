import 'package:dio/dio.dart';

/// Lỗi theo định dạng chung của backend: {"error": {"code", "message", "details"}} (đặc tả mục 9.5).
class ApiError implements Exception {
  ApiError(this.status, this.code, this.message, [this.details = const {}]);

  final int status;
  final String code;
  final String message;
  final Object details;

  factory ApiError.fromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiError(e.response!.statusCode ?? 0, '${err['code']}', '${err['message']}', err['details'] ?? const {});
    }
    if (e.response == null) {
      return ApiError(0, 'NETWORK_ERROR', 'Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.');
    }
    return ApiError(e.response!.statusCode ?? 0, 'HTTP_ERROR', 'Máy chủ gặp lỗi, vui lòng thử lại sau.');
  }

  @override
  String toString() => 'ApiError($status, $code, $message)';
}
