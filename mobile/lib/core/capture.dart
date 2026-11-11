import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

/// Người dùng từ chối quyền camera (hoặc máy không có camera).
class CameraDenied implements Exception {
  const CameraDenied([this.noCamera = false]);
  final bool noCamera;
}

/// Camera trước dùng cho đăng ký khuôn mặt và điểm danh. Tách interface để widget test dùng camera giả.
abstract class FaceCamera {
  /// Ném [CameraDenied] khi không có quyền hoặc không có camera.
  Future<void> init();
  Widget preview();
  Future<Uint8List> capture();
  Future<void> dispose();
}

class DeviceCamera implements FaceCamera {
  CameraController? _c;

  @override
  Future<void> init() async {
    final cams = await availableCameras();
    if (cams.isEmpty) throw const CameraDenied(true);
    final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
    // high = 720p: cạnh dài ≤ 1280 px như đặc tả mục 5.2, không cần thu nhỏ thêm.
    final c = CameraController(front, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    try {
      await c.initialize();
    } on CameraException catch (e) {
      await c.dispose();
      if (e.code.contains('Denied') || e.code.contains('denied') || e.code.contains('NotAllowed')) {
        throw const CameraDenied();
      }
      rethrow;
    }
    _c = c;
  }

  @override
  Widget preview() => _c == null ? const SizedBox.shrink() : CameraPreview(_c!);

  @override
  Future<Uint8List> capture() => captureJpeg(_c!);

  @override
  Future<void> dispose() async => _c?.dispose();
}

/// Chụp một khung JPEG từ camera đang mở.
Future<Uint8List> captureJpeg(CameraController c) async => (await c.takePicture()).readAsBytes();
