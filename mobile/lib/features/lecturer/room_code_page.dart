import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import 'live_session_page.dart' show pollEvery;

/// Artboard "Web · Chiếu mã phòng" (Web_ChieuMaPhong.dc.html), mở trên laptop nối máy chiếu.
/// GET /sessions/{id}/room-token, lấy mã mới khi hết cửa sổ 30 s; số đã điểm danh lấy từ /records.
class RoomCodePage extends StatefulWidget {
  const RoomCodePage({super.key, required this.session, required this.sessionId});
  final Session session;
  final int sessionId;

  @override
  State<RoomCodePage> createState() => _RoomCodePageState();
}

class _RoomCodePageState extends State<RoomCodePage> {
  Map<String, dynamic>? _token;
  Map<String, dynamic>? _info;
  String? _error;
  Timer? _tick;
  DateTime _lastInfo = DateTime(0);

  @override
  void initState() {
    super.initState();
    _refresh();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final ends = _windowEnds;
      if (_error == null && ends != null && !clock.now().isBefore(ends)) _refresh();
      if (clock.now().difference(_lastInfo) >= pollEvery) _loadInfo();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  DateTime? get _windowEnds => _token == null ? null : DateTime.parse('${_token!['window_ends_at']}').toLocal();

  bool _fetching = false;

  Future<void> _refresh() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final t = await widget.session.api.get('/sessions/${widget.sessionId}/room-token') as Map;
      if (mounted) {
        setState(() {
          _token = Map<String, dynamic>.from(t);
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message); // vd phiên đã đóng: dừng, không hỏi lại
    } finally {
      _fetching = false;
    }
    if (_info == null) _loadInfo();
  }

  Future<void> _loadInfo() async {
    _lastInfo = clock.now();
    try {
      final r = await widget.session.api.get('/sessions/${widget.sessionId}/records') as Map;
      if (mounted) setState(() => _info = Map<String, dynamic>.from(r));
    } on ApiError catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = _info?['session'] as Map?;
    final counts = _info?['counts'] as Map?;
    final done = counts == null ? null : (counts['present'] as int) + (counts['manual_present'] as int) + (counts['suspicious'] as int);
    final total = counts?.values.fold<int>(0, (a, b) => a + (b as int));
    final ends = _windowEnds;
    final codeLeft = ends == null ? 0 : ends.difference(clock.now()).inSeconds.clamp(0, 30);
    final sessionLeft = s == null ? 0 : DateTime.parse('${s['expires_at']}').toLocal().difference(clock.now()).inSeconds.clamp(0, 99 * 60);
    final code = '${_token?['code'] ?? ''}';

    final qr = Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32),
          boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 64, offset: Offset(0, 24))]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox.square(
          dimension: 440,
          child: _token == null
              ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!, textAlign: TextAlign.center))
              : QrImageView(data: '${_token!['qr_payload']}', padding: EdgeInsets.zero,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.hero),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppColors.hero)),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 440,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: codeLeft / 30, minHeight: 8, color: AppColors.primary,
                backgroundColor: AppColors.inputBorder),
          ),
        ),
      ]),
    );

    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Pill(s?['is_open'] == false ? 'Phiên đã đóng' : 'Đang mở điểm danh', dot: true,
          bg: const Color(0x2610B981), fg: const Color(0xFF6EE7B7), border: const Color(0x4D10B981),
          fontSize: 16, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
      const SizedBox(height: 12),
      Text('${s?['class']['name'] ?? ''}',
          style: const TextStyle(fontSize: 60, height: 68 / 60, fontWeight: FontWeight.w800, letterSpacing: -1.2, color: Colors.white)),
      Text('${s?['class']['code'] ?? ''}', style: const TextStyle(fontSize: 22, color: Color(0xFF94A3B8))),
      const SizedBox(height: 30),
      for (final (i, t) in const [
        ('Mở ứng dụng, bấm ', 'Điểm danh ngay'),
        ('Quét mã QR này', ''),
        ('Làm theo hướng dẫn chụp khuôn mặt', ''),
      ].indexed) ...[
        Row(children: [
          Container(
            width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x1FFFFFFF))),
            child: Text('${i + 1}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFFA5B4FC))),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text.rich(TextSpan(style: const TextStyle(fontSize: 24, height: 32 / 24, color: Color(0xFFE2E8F0)), children: [
              TextSpan(text: t.$1),
              TextSpan(text: t.$2, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
            ])),
          ),
        ]),
        const SizedBox(height: 14),
      ],
      const SizedBox(height: 16),
      Row(children: [
        _Stat('Mã đổi sau', '$codeLeft s', const Color(0xFFA5B4FC)),
        const SizedBox(width: 14),
        _Stat('Phiên còn', '${(sessionLeft ~/ 60).toString().padLeft(2, '0')}:${(sessionLeft % 60).toString().padLeft(2, '0')}',
            const Color(0xFFFCD34D)),
        const SizedBox(width: 14),
        _Stat('Đã điểm danh', done == null ? '–' : '$done', const Color(0xFF34D399), suffix: total == null ? null : ' / $total'),
      ]),
      const SizedBox(height: 30),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Không quét được? Nhập mã ', style: TextStyle(fontSize: 18, color: Color(0xFF94A3B8))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(10)),
          child: Text(code.length == 8 ? '${code.substring(0, 4)} ${code.substring(4)}' : code,
              style: mono.copyWith(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 4, color: Colors.white)),
        ),
      ]),
    ]);

    return Scaffold(
      backgroundColor: AppColors.hero,
      body: Stack(children: [
        const Positioned(right: -120, top: -160, child: _Blob(520, Color(0x594F46E5))),
        const Positioned(left: 300, bottom: -220, child: _Blob(460, Color(0x2E10B981))),
        LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 1100;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: wide ? 80 : 24, vertical: wide ? 56 : 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight - (wide ? 112 : 48)),
              child: wide
                  ? Row(children: [qr, const SizedBox(width: 72), Expanded(child: info)])
                  : Column(children: [FittedBox(child: qr), const SizedBox(height: 32), info]),
            ),
          );
        }),
        Positioned(
          top: 16, left: 16,
          child: IconButton(
            tooltip: 'Quay lại',
            onPressed: () => context.canPop() ? context.pop() : context.go('/lecturer'),
            icon: const Icon(Icons.close, color: Color(0x99FFFFFF)),
          ),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color, {this.suffix});
  final String label;
  final String value;
  final Color color;
  final String? suffix;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x14FFFFFF))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 15, color: Color(0xFF94A3B8))),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(TextSpan(children: [
                TextSpan(text: value, style: mono.copyWith(fontSize: 36, fontWeight: FontWeight.w800, color: color)),
                if (suffix != null) TextSpan(text: suffix, style: mono.copyWith(fontSize: 22, color: const Color(0xFF94A3B8))),
              ])),
            ),
          ]),
        ),
      );
}

class _Blob extends StatelessWidget {
  const _Blob(this.size, this.color);
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 45, sigmaY: 45, tileMode: TileMode.decal),
          child: Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        ),
      );
}
