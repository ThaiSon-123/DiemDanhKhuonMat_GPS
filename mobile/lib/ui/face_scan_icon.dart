import 'package:flutter/material.dart';

/// Biểu tượng "khuôn mặt trong khung quét" của thiết kế (logo app), vẽ lại từ SVG 24×24.
class FaceScanIcon extends StatelessWidget {
  const FaceScanIcon({super.key, this.size = 24, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _FaceScanPainter(color));
}

class _FaceScanPainter extends CustomPainter {
  _FaceScanPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Bốn góc khung quét.
    final corners = Path()
      ..moveTo(4, 8)..lineTo(4, 6)..quadraticBezierTo(4, 4, 6, 4)..lineTo(8, 4)
      ..moveTo(16, 4)..lineTo(18, 4)..quadraticBezierTo(20, 4, 20, 6)..lineTo(20, 8)
      ..moveTo(20, 16)..lineTo(20, 18)..quadraticBezierTo(20, 20, 18, 20)..lineTo(16, 20)
      ..moveTo(8, 20)..lineTo(6, 20)..quadraticBezierTo(4, 20, 4, 18)..lineTo(4, 16);
    canvas.drawPath(corners, p);
    canvas.drawCircle(const Offset(12, 10), 2.6, p);
    // Vai: cung nửa trên của elip.
    canvas.drawArc(const Rect.fromLTRB(8, 12.5, 16, 20.5), 3.6, 2.2, false, p);
  }

  @override
  bool shouldRepaint(_FaceScanPainter old) => old.color != color;
}
