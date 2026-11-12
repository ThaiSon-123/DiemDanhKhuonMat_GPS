import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'face_scan_icon.dart';
import 'theme.dart';
import 'web_shell.dart';

/// Chữ đơn cách cho mã, giờ, số liệu (canvas: ui-monospace, Consolas, monospace).
const mono = TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Consolas', 'Menlo', 'Courier New']);

/// Chữ viết tắt cho avatar: chữ đầu của từ đầu và từ cuối, bỏ học hàm ("TS.", "ThS.").
String initials(String name) {
  final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty && !w.endsWith('.')).toList();
  if (words.isEmpty) return '?';
  final first = words.first.characters.first;
  return words.length == 1 ? first.toUpperCase() : (first + words.last.characters.first).toUpperCase();
}

/// "Thứ Ba, 10/11"
String vnDate(DateTime d) {
  const days = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ nhật'];
  return '${days[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

void comingSoon(BuildContext context, [String what = 'Chức năng này']) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$what đang được xây dựng.'), behavior: SnackBarBehavior.floating));
}

/// Ô vuông trắng bo 16 chứa logo / icon ở đầu trang.
class HeaderTile extends StatelessWidget {
  const HeaderTile({super.key, required this.child, this.size = 40, this.onTap, this.tooltip});
  final Widget child;
  final double size;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tile = Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      shadowColor: const Color(0x1A0F172A),
      elevation: 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox.square(dimension: size, child: Center(child: child)),
      ),
    );
    return tooltip == null ? tile : Tooltip(message: tooltip!, child: tile);
  }
}

/// Đầu trang mờ kính cao 64: logo (hoặc nút quay lại), nhãn nhỏ màu indigo, tiêu đề, phần bên phải.
class NeoHeader extends StatelessWidget {
  const NeoHeader({super.key, required this.label, required this.title, this.trailing = const [], this.onBack, this.backIcon = Icons.arrow_back});
  final String label;
  final String title;
  final List<Widget> trailing;

  /// Có giá trị thì thay logo bằng nút quay lại.
  final VoidCallback? onBack;
  final IconData backIcon;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: Color(0xD9F6F8FC),
            border: Border(bottom: BorderSide(color: Color(0x99E2E8F0))),
          ),
          child: Row(children: [
            if (onBack == null)
              const HeaderTile(child: FaceScanIcon(size: 22, color: AppColors.primary))
            else
              HeaderTile(
                tooltip: 'Quay lại',
                onTap: onBack,
                child: Icon(backIcon, size: 20, color: AppColors.textSecondary),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: AppColors.primary)),
                Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
              ]),
            ),
            for (final w in trailing) ...[const SizedBox(width: 8), w],
          ]),
        ),
      ),
    );
  }
}

/// Avatar chữ viết tắt bo 16, có vòng trắng; [verified] thêm chấm xanh có dấu tích.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.bg = AppColors.primarySoft, this.fg = const Color(0xFF4338CA),
      this.verified = false, this.size = 40, this.round = false});
  final String name;
  final Color bg;
  final Color fg;
  final bool verified;
  final double size;
  final bool round;

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(round ? size / 2 : 16),
          boxShadow: const [BoxShadow(color: Colors.white, spreadRadius: 2)],
        ),
        child: Text(initials(name), style: TextStyle(fontSize: size * 0.35, fontWeight: FontWeight.w700, color: fg)),
      ),
      if (verified)
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 14,
            height: 14,
            decoration: const BoxDecoration(
              color: AppColors.present,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.white, spreadRadius: 2)],
            ),
            child: const Icon(Icons.check, size: 10, color: Colors.white),
          ),
        ),
    ]);
  }
}

/// Viên thuốc nhỏ có viền: nhãn trạng thái, mã lớp...
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.bg, required this.fg, this.border, this.icon, this.dot = false,
      this.monospace = false, this.radius = 999, this.fontSize = 11, this.padding});
  final String text;
  final Color bg;
  final Color fg;
  final Color? border;
  final IconData? icon;
  final bool dot;
  final bool monospace;
  final double radius;
  final double fontSize;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(width: 7, height: 7, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        if (icon != null) ...[Icon(icon, size: fontSize + 3, color: fg), const SizedBox(width: 4)],
        Text(text,
            style: (monospace ? mono : const TextStyle())
                .copyWith(fontSize: fontSize, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

/// Mã lớp dạng chip đơn cách.
class CodeChip extends StatelessWidget {
  const CodeChip(this.code, {super.key, this.dark = false});
  final String code;
  final bool dark;

  @override
  Widget build(BuildContext context) => dark
      ? Pill(code, bg: const Color(0x336366F1), fg: const Color(0xFFA5B4FC), border: const Color(0x4D818CF8),
          monospace: true, radius: 8, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2))
      : Pill(code, bg: AppColors.cardBorder, fg: AppColors.textLabel, monospace: true, radius: 6,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2));
}

/// Đồng hồ đếm ngược mm:ss tới [until], dạng viên thuốc vàng trên nền tối.
class CountdownPill extends StatefulWidget {
  const CountdownPill({super.key, required this.until});
  final DateTime until;

  @override
  State<CountdownPill> createState() => _CountdownPillState();
}

class _CountdownPillState extends State<CountdownPill> {
  late final Timer _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.until.difference(DateTime.now());
    final s = left.isNegative ? 0 : left.inSeconds;
    final text = '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
    return Semantics(
      label: 'Còn $text',
      child: Pill(text, bg: const Color(0x26F59E0B), fg: const Color(0xFFFCD34D), border: const Color(0x4DF59E0B),
          icon: Icons.hourglass_top, monospace: true, fontSize: 12,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
    );
  }
}

/// Nhãn "đang mở" màu hồng có chấm.
class LivePill extends StatelessWidget {
  const LivePill(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Pill(text.toUpperCase(), bg: const Color(0x26F43F5E), fg: const Color(0xFFFB7185),
      border: const Color(0x4DF43F5E), dot: true, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4));
}

class DockItem {
  const DockItem(this.icon, this.label, {this.badge});
  final IconData icon;
  final String label;
  final int? badge;
}

/// Thanh điều hướng nổi dạng viên thuốc ở đáy (canvas: left/right 16, bottom 14, cao 64).
class NeoDock extends StatelessWidget {
  const NeoDock({super.key, required this.items, required this.current, required this.onTap});
  final List<DockItem> items;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xEBFFFFFF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xCCE2E8F0)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            for (final (i, it) in items.indexed) Expanded(child: _item(i, it)),
          ]),
        ),
      ),
    );
  }

  Widget _item(int i, DockItem it) {
    final active = i == current;
    final color = active ? AppColors.primary : AppColors.textMuted;
    return Semantics(
      selected: active,
      button: true,
      label: it.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => onTap(i),
        child: SizedBox(
          height: 52,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: active ? AppColors.primarySoft : null, shape: BoxShape.circle),
                child: Icon(it.icon, size: active ? 20 : 22, color: color),
              ),
              if (it.badge != null && it.badge! > 0)
                Positioned(
                  top: -2,
                  right: -6,
                  child: Pill('${it.badge}', bg: AppColors.absent, fg: Colors.white, fontSize: 10,
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1)),
                ),
            ]),
            const SizedBox(height: 2),
            ExcludeSemantics(
              child: Text(it.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: color)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Khung trang điện thoại có đầu trang và dock: nội dung cuộn, chừa chỗ cho dock; màn rộng giữ khổ 480px.
class PhoneShell extends StatelessWidget {
  const PhoneShell({super.key, required this.header, required this.dock, required this.body});
  final Widget header;
  final Widget dock;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Stack(children: [
              Column(children: [header, Expanded(child: body)]),
              if (!InWebShell.of(context)) Positioned(left: 16, right: 16, bottom: 14, child: dock), // web: thanh bên thay dock
            ]),
          ),
        ),
      ),
    );
  }
}

/// Trạng thái tải / lỗi chung cho màn lấy dữ liệu.
class LoadingOrError extends StatelessWidget {
  const LoadingOrError({super.key, this.error, required this.onRetry});
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error == null) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Thử lại')),
        ]),
      ),
    );
  }
}
