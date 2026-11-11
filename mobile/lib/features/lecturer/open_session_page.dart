import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/gps_sampler.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import '../student/permissions_page.dart';

const _maxAcc = 20.0, _minGood = 5;

/// Artboard "GV · Mở phiên" (GV_MoPhien.dc.html). Tâm phiên = vị trí giảng viên (đặc tả 4.3, 6.1):
/// gom mẫu 20 m / 5 mẫu / 3 s / 20 s; nút mở chỉ bật khi đủ mẫu. POST /sessions rồi sang "Phiên đang chạy".
class OpenSessionPage extends StatefulWidget {
  const OpenSessionPage({super.key, required this.session, required this.classId, this.classCode = '',
      this.studentCount, this.gpsSource});
  final Session session;
  final int classId;
  final String classCode;
  final int? studentCount;
  final Stream<GpsSample> Function()? gpsSource;

  @override
  State<OpenSessionPage> createState() => _OpenSessionPageState();
}

class _OpenSessionPageState extends State<OpenSessionPage> {
  int _duration = 10;
  double _r0 = 20;
  bool _room = true;
  double? _acc;
  int _good = 0;
  List<GpsSample>? _samples;
  bool _denied = false;
  bool _busy = false;
  String? _error;
  final _subs = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    _collect();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _collect() async {
    setState(() {
      _samples = null;
      _error = null;
      _denied = false;
      _good = 0;
      _acc = null;
    });
    final sampler = GpsSampler((widget.gpsSource ?? deviceGps)(),
        maxAcc: _maxAcc, minGood: _minGood, minDuration: const Duration(seconds: 3), timeout: const Duration(seconds: 20));
    _subs
      ..add(sampler.currentAccuracy.listen((a) => mounted ? setState(() => _acc = a) : null))
      ..add(sampler.goodCount.listen((g) => mounted ? setState(() => _good = g) : null));
    try {
      final s = await sampler.collect();
      if (mounted) setState(() => _samples = s);
    } on GpsTimeout {
      if (mounted) setState(() => _error = 'Chưa đủ $_minGood mẫu GPS ≤ ${_maxAcc.round()} m. Đứng yên, bật Wi-Fi rồi thử lại.');
    } on LocationDenied catch (e) {
      if (mounted) {
        setState(() => e.serviceOff ? _error = 'Định vị của máy đang tắt. Hãy bật Vị trí rồi thử lại.' : _denied = true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Không lấy được vị trí: $e');
    }
  }

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.session.api.post('/sessions', data: {
        'class_id': widget.classId,
        'duration_min': _duration,
        'base_radius_m': _r0,
        'room_check': _room,
        'gps_samples': [for (final s in _samples!) s.toJson()],
      }) as Map;
      if (mounted) context.go('/lecturer/session/${r['session_id']}');
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      if (e.code == 'GPS_ACCURACY_LOW') _collect();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_denied) {
      return PermissionsPage(kind: PermissionKind.location, onRetry: _collect, onLater: () => context.go('/lecturer'));
    }
    final good = _good.clamp(0, _minGood);
    final ready = _samples != null;
    final label = [widget.classCode, if (widget.studentCount != null) '${widget.studentCount} sinh viên'].join(' · ');
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(children: [
              NeoHeader(label: label, title: 'Mở phiên điểm danh', onBack: () => context.go('/lecturer')),
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
                  HeroCard(
                    emeraldGlow: false,
                    padding: const EdgeInsets.all(18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        SizedBox.square(
                          dimension: 60,
                          child: Stack(alignment: Alignment.center, children: [
                            Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x1FFFFFFF)))),
                            Container(width: 38, height: 38, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x406366F1))),
                            const Icon(Icons.my_location, size: 22, color: Color(0xFFA5B4FC)),
                          ]),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Tâm phiên = vị trí của bạn', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            SizedBox(height: 2),
                            Text('Đứng yên ở bục giảng', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                          ]),
                        ),
                        Text(_acc == null ? '…' : '±${_acc!.round()} m',
                            style: mono.copyWith(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                      ]),
                      const SizedBox(height: 14),
                      Row(children: [
                        for (var i = 0; i < _minGood; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(child: Container(height: 8, decoration: BoxDecoration(
                              color: i < good ? const Color(0xFF34D399) : const Color(0x26FFFFFF),
                              borderRadius: BorderRadius.circular(4)))),
                        ],
                      ]),
                      const SizedBox(height: 14),
                      Pill('$good/$_minGood mẫu ≤ ${_maxAcc.round()} m', bg: const Color(0x2610B981), fg: const Color(0xFF6EE7B7),
                          border: const Color(0x4D10B981), monospace: true),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  NeoCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('Thời hạn phiên', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
                      const SizedBox(height: 10),
                      Segmented(
                        options: const ['5 phút', '10 phút', '15 phút'],
                        selected: [5, 10, 15].indexOf(_duration),
                        onChanged: (i) => setState(() => _duration = [5, 10, 15][i]),
                      ),
                      const SizedBox(height: 18),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Bán kính cơ sở r₀', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
                        Pill('${_r0.round()} m', bg: AppColors.primarySoft, fg: const Color(0xFF4338CA), border: const Color(0xFFE0E7FF),
                            monospace: true, fontSize: 12),
                      ]),
                      Slider(value: _r0, min: 10, max: 50, divisions: 8, onChanged: (v) => setState(() => _r0 = v)),
                      const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('10 m · chặt', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        Text('50 m · rộng', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ]),
                      const SizedBox(height: 14),
                      Row(children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
                          child: const Icon(Icons.qr_code_2, size: 21, color: AppColors.primary),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Bật mã phòng', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                            Text('Chiếu QR từ laptop để xác nhận đúng phòng', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          ]),
                        ),
                        Switch(value: _room, onChanged: (v) => setState(() => _room = v)),
                      ]),
                    ]),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    ErrorNote(_error!),
                    if (!ready) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(onPressed: _collect, icon: const Icon(Icons.refresh, size: 18), label: const Text('Lấy lại vị trí')),
                    ],
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 52,
                    child: FilledButton(onPressed: ready && !_busy ? _open : null,
                        child: Text(_busy ? 'Đang mở…' : 'Mở phiên điểm danh')),
                  ),
                  if (!ready) ...[
                    const SizedBox(height: 8),
                    Text('Cần thêm ${_minGood - good} mẫu GPS đạt yêu cầu', textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Nhóm nút chọn một (nền xám, ô chọn trắng nổi), dùng cho thời hạn phiên và bộ lọc.
class Segmented extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.selected, required this.onChanged,
      this.dark = false, this.background = const Color(0xFFF1F5F9)});
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  /// Ô chọn nền tối (bộ lọc trong "Phiên đang chạy").
  final bool dark;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(16),
            border: dark ? Border.all(color: AppColors.cardBorder) : null),
        child: Row(children: [
          for (final (i, o) in options.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Material(
                color: i == selected ? (dark ? AppColors.text : Colors.white) : Colors.transparent,
                elevation: i == selected && !dark ? 1 : 0,
                shadowColor: const Color(0x1A0F172A),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onChanged(i),
                  child: Container(
                    constraints: BoxConstraints(minHeight: dark ? 36 : 40),
                    alignment: Alignment.center,
                    child: Text(o, style: TextStyle(
                        fontSize: dark ? 12 : 14,
                        fontWeight: i == selected ? FontWeight.w700 : FontWeight.w400,
                        color: i == selected ? (dark ? Colors.white : AppColors.text) : AppColors.textSecondary)),
                  ),
                ),
              ),
            ),
          ],
        ]),
      );
}
