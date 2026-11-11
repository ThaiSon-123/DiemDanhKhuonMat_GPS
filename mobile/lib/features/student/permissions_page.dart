import 'package:flutter/material.dart';

import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';

enum PermissionKind { camera, location, bluetooth }

const _texts = {
  PermissionKind.camera: (
    Icons.photo_camera_outlined,
    'Cần quyền dùng camera',
    'Camera dùng để chụp khuôn mặt khi đăng ký và điểm danh. Ảnh không được lưu trên điện thoại.',
    'Bật Camera: Cho phép khi dùng ứng dụng',
  ),
  PermissionKind.location: (
    Icons.my_location,
    'Cần quyền vị trí chính xác',
    'Vị trí chỉ được lấy khi bạn bấm điểm danh, để xác nhận bạn đang ở lớp. Không theo dõi liên tục.',
    'Bật Vị trí và Vị trí chính xác',
  ),
  PermissionKind.bluetooth: (
    Icons.bluetooth,
    'Cần quyền Bluetooth',
    'Bluetooth dùng để nhận mã phòng từ thiết bị của giảng viên. Không cần ghép đôi.',
    'Bật Thiết bị lân cận (Bluetooth)',
  ),
};

/// Artboard "SV · Quyền truy cập" (SV_QuyenTruyCap.dc.html), dùng lại cho camera, vị trí, Bluetooth.
/// Chưa mở thẳng trang Cài đặt (cần thêm plugin); hiện hướng dẫn và nút thử lại.
class PermissionsPage extends StatelessWidget {
  const PermissionsPage({super.key, required this.kind, required this.onRetry, required this.onLater});
  final PermissionKind kind;
  final VoidCallback onRetry;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final (icon, title, why, step3) = _texts[kind]!;
    final steps = [
      const Text.rich(TextSpan(children: [TextSpan(text: 'Mở '), TextSpan(text: 'Cài đặt', style: TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: ' của điện thoại (hoặc biểu tượng ổ khóa trên thanh địa chỉ trình duyệt)')])),
      const Text.rich(TextSpan(children: [TextSpan(text: 'Chọn '), TextSpan(text: 'Quyền', style: TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: ' của ứng dụng Điểm danh')])),
      Text(step3),
    ];
    return NeoPage(
      bottom: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 18), label: const Text('Thử lại')),
        const SizedBox(height: 8),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: AppColors.textSecondary),
          onPressed: onLater,
          child: const Text('Để sau', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ]),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: HeaderTile(tooltip: 'Đóng', onTap: onLater, child: const Icon(Icons.close, size: 20, color: AppColors.textSecondary)),
        ),
        HeroCard(
          emeraldGlow: false,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
          child: Column(children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: const Color(0x336366F1),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0x59818CF8)),
                ),
                child: Icon(icon, size: 42, color: const Color(0xFFA5B4FC)),
              ),
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: AppColors.absent,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: AppColors.hero, spreadRadius: 3)],
                  ),
                  child: const Icon(Icons.block, size: 16, color: Colors.white),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Text(why, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, height: 20 / 14, color: AppColors.heroText)),
          ]),
        ),
        NeoCard(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            for (final (i, s) in steps.indexed) ...[
              if (i > 0) const SizedBox(height: 10),
              Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
                  child: Text('${i + 1}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary)),
                ),
                const SizedBox(width: 12),
                Expanded(child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 14, color: AppColors.text), child: s)),
              ]),
            ],
          ]),
        ),
      ],
    );
  }
}
