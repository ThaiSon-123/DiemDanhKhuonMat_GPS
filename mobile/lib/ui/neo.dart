import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Trang Neo-Widget không thanh điều hướng: cột cuộn trên nền #F6F8FC, khoảng cách 14,
/// [bottom] luôn dính đáy khi nội dung ngắn. Màn rộng giữ khổ điện thoại 480px ở giữa.
class NeoPage extends StatelessWidget {
  const NeoPage({super.key, required this.children, this.bottom});
  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight - 40),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, w) in children.indexed) ...[
                          if (i > 0) const SizedBox(height: 14),
                          w,
                        ],
                        if (bottom != null) ...[
                          const Spacer(),
                          const SizedBox(height: 14),
                          bottom!,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Widget "hòn đảo" tối #090D16 bo 24 với quầng sáng indigo (phải trên) và emerald (trái dưới).
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.emeraldGlow = true,
  });
  final Widget child;
  final EdgeInsets padding;
  final bool emeraldGlow;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.hero,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.heroBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59090D16),
            blurRadius: 40,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned(
            top: -56,
            right: -56,
            child: _Glow(size: 176, color: AppColors.glowIndigo, blur: 40),
          ),
          if (emeraldGlow)
            const Positioned(
              bottom: -40,
              left: -40,
              child: _Glow(size: 144, color: AppColors.glowEmerald, blur: 32),
            ),
          Padding(
            padding: padding,
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Colors.white),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color, required this.blur});
  final double size;
  final Color color;
  final double blur;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ImageFiltered(
      imageFilter: ImageFilter.blur(
        sigmaX: blur / 2,
        sigmaY: blur / 2,
        tileMode: TileMode.decal,
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    ),
  );
}

/// Thẻ trắng bo 24, viền #F1F5F9, bóng rất nhẹ.
class NeoCard extends StatelessWidget {
  const NeoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.cardBorder),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A0F172A),
          blurRadius: 24,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

/// Hộp báo lỗi hồng nhạt có biểu tượng, dùng dưới ô nhập.
class ErrorNote extends StatelessWidget {
  const ErrorNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.absentSoft,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.absentBorder),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error, size: 16, color: AppColors.absentText),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              height: 17 / 12,
              color: AppColors.absentText,
            ),
          ),
        ),
      ],
    ),
  );
}
