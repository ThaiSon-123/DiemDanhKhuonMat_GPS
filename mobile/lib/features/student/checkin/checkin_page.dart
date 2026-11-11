import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/capture.dart';
import '../../../core/device_id.dart';
import '../../../core/gps_sampler.dart';
import '../../../core/session.dart';
import '../../../ui/neo.dart';
import '../../../ui/neo_parts.dart';
import '../../../ui/theme.dart';
import '../permissions_page.dart';
import 'checkin_controller.dart';

const _frameCount = 6;
const _frameGap = Duration(milliseconds: 350); // 6 khung trong ~2 giây khi sinh viên làm hành động
const _actions = {
  'turn_left': ('Quay đầu sang trái', Icons.turn_left),
  'turn_right': ('Quay đầu sang phải', Icons.turn_right),
};

/// Luồng điểm danh của sinh viên. Artboard SV_DiemDanhGPS, SV_DiemDanhCamera, SV_KetQua; bước quét mã phòng
/// không có artboard riêng nên theo bố cục bước vị trí, kèm ô nhập mã tay.
class CheckinPage extends StatefulWidget {
  const CheckinPage({
    super.key,
    required this.session,
    required this.sessionId,
    this.classCode = '',
    this.className = '',
    this.camera,
    this.gpsSource,
    this.scanner,
    this.deviceId,
  });
  final Session session;
  final int sessionId;
  final String classCode;
  final String className;
  final FaceCamera? camera;
  final Stream<GpsSample> Function()? gpsSource;
  final Widget Function(ValueChanged<String> onCode)? scanner;
  final Future<String> Function()? deviceId;

  @override
  State<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends State<CheckinPage> {
  late final CheckinController c = CheckinController(
    api: widget.session.api,
    sessionId: widget.sessionId,
    gpsSource: widget.gpsSource ?? deviceGps,
    deviceId: widget.deviceId ?? deviceId,
  )..addListener(_changed);
  late final Timer _tick = Timer.periodic(const Duration(seconds: 1), (_) {
    c.checkExpired();
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    _tick;
    c.start();
  }

  @override
  void dispose() {
    _tick.cancel();
    c.removeListener(_changed);
    c.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _home() => context.go('/student');

  @override
  Widget build(BuildContext context) {
    if (c.step == CheckinStep.gps && c.locationDenied) {
      return PermissionsPage(kind: PermissionKind.location, onRetry: c.collectGps, onLater: _home);
    }
    if (c.step == CheckinStep.camera) {
      return _CameraStep(controller: c, camera: widget.camera ?? DeviceCamera(), onCancel: _home);
    }
    final live = {CheckinStep.roomCode, CheckinStep.gps}.contains(c.step);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(children: [
              NeoHeader(
                label: [widget.classCode, widget.className].where((s) => s.isNotEmpty).join(' · '),
                title: c.step == CheckinStep.result ? 'Kết quả điểm danh' : 'Điểm danh',
                onBack: _home,
                backIcon: live ? Icons.close : Icons.arrow_back,
                trailing: [if (live) _timerPill(c.secondsLeft)],
              ),
              Expanded(child: _body()),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _body() => switch (c.step) {
        CheckinStep.challenge => _challenge(),
        CheckinStep.roomCode => _RoomCodeStep(controller: c, scanner: widget.scanner),
        CheckinStep.gps => _gps(),
        CheckinStep.submitting => const _Waiting('Đang kiểm tra lượt điểm danh…'),
        CheckinStep.result => _ResultStep(controller: c, classCode: widget.classCode, className: widget.className,
            onHome: _home, onEnroll: () => context.go('/student/face')),
        CheckinStep.camera => const SizedBox.shrink(),
      };

  Widget _challenge() {
    if (c.error == null) return const _Waiting('Đang nhận thử thách…');
    return ListView(padding: const EdgeInsets.all(16), children: [
      ErrorNote(c.error!),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: c.retry, icon: const Icon(Icons.refresh, size: 18), label: const Text('Bắt đầu lại')),
    ]);
  }

  Widget _gps() {
    final acc = c.accuracy;
    final good = c.goodSamples.clamp(0, CheckinController.studentMinGood);
    final ok = acc != null && acc <= CheckinController.studentMaxAcc;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
      _Steps(roomCheck: c.roomCheck, current: 1),
      const SizedBox(height: 12),
      HeroCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        child: Column(children: [
          const _Radar(),
          const SizedBox(height: 16),
          const Text('ĐỘ CHÍNH XÁC HIỆN TẠI', style: TextStyle(fontSize: 12, letterSpacing: 0.5, color: Color(0xFF94A3B8))),
          const SizedBox(height: 4),
          Text(acc == null ? '…' : '±${acc.round()} m',
              style: mono.copyWith(fontSize: 40, height: 46 / 40, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 4),
          if (acc != null)
            Pill(ok ? 'Đạt yêu cầu ≤ 30 m' : 'Chưa đạt, cần ≤ 30 m',
                icon: ok ? Icons.check_circle : Icons.error_outline,
                bg: ok ? const Color(0x2610B981) : const Color(0x26F59E0B),
                fg: ok ? const Color(0xFF6EE7B7) : const Color(0xFFFCD34D),
                border: ok ? const Color(0x4D10B981) : const Color(0x4DF59E0B), fontSize: 12),
        ]),
      ),
      const SizedBox(height: 12),
      NeoCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Đang lấy mẫu vị trí', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
            Pill('$good/${CheckinController.studentMinGood} mẫu', bg: AppColors.primarySoft, fg: const Color(0xFF4338CA),
                border: const Color(0xFFE0E7FF), monospace: true, fontSize: 12),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            for (var i = 0; i < CheckinController.studentMinGood; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Container(height: 8, decoration: BoxDecoration(
                    color: i < good ? AppColors.primary : AppColors.cardBorder, borderRadius: BorderRadius.circular(4))),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.wifi, size: 17, color: AppColors.primary),
            SizedBox(width: 8),
            Expanded(
              child: Text('Bật Wi-Fi để định vị trong phòng chính xác hơn. Chờ lâu thì lại gần cửa sổ.',
                  style: TextStyle(fontSize: 12, height: 17 / 12, color: AppColors.textSecondary)),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      if (c.error != null) ...[
        ErrorNote(c.error!),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: c.collectGps, icon: const Icon(Icons.refresh, size: 18), label: const Text('Lấy lại vị trí')),
      ] else
        FilledButton(onPressed: null, child: Text('Tiếp tục khi đủ ${CheckinController.studentMinGood} mẫu')),
    ]);
  }
}

Widget _timerPill(int s) => Pill('${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}',
    icon: Icons.hourglass_top, bg: const Color(0xFFFFFBEB), fg: const Color(0xFF92400E), border: const Color(0xFFFDE68A),
    monospace: true, fontSize: 12, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5));

class _Waiting extends StatelessWidget {
  const _Waiting(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(text, style: const TextStyle(color: AppColors.textSecondary)),
        ]),
      );
}

/// Ba bước Mã phòng / Vị trí / Khuôn mặt (bỏ Mã phòng khi phiên không bật). [current]: 0 mã phòng, 1 vị trí, 2 mặt.
class _Steps extends StatelessWidget {
  const _Steps({required this.roomCheck, required this.current});
  final bool roomCheck;
  final int current;

  @override
  Widget build(BuildContext context) {
    final steps = [
      if (roomCheck) (0, 'Mã phòng', Icons.qr_code_scanner),
      (1, 'Vị trí', Icons.share_location),
      (2, 'Khuôn mặt', Icons.face),
    ];
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.cardBorder)),
      child: Row(children: [
        for (final (i, (n, label, icon)) in steps.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: n < current ? AppColors.presentSoft : n == current ? AppColors.primary : null,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(n < current ? Icons.check_circle : icon, size: 15,
                    color: n < current ? AppColors.presentText : n == current ? Colors.white : AppColors.textMuted),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: n == current ? FontWeight.w700 : FontWeight.w600,
                    color: n < current ? AppColors.presentText : n == current ? Colors.white : AppColors.textMuted)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Radar extends StatelessWidget {
  const _Radar();

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 200,
        child: Stack(alignment: Alignment.center, children: [
          for (final (d, a) in const [(200.0, 0x1A), (140.0, 0x1F)])
            Container(width: d, height: d, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Color.fromARGB(a, 255, 255, 255)))),
          Container(width: 92, height: 92, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x336366F1),
              border: Border.all(color: const Color(0x80818CF8)))),
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Color(0x404F46E5), spreadRadius: 8)]),
            child: const Icon(Icons.location_on, size: 24, color: Colors.white),
          ),
        ]),
      );
}

class _RoomCodeStep extends StatefulWidget {
  const _RoomCodeStep({required this.controller, this.scanner});
  final CheckinController controller;
  final Widget Function(ValueChanged<String> onCode)? scanner;

  @override
  State<_RoomCodeStep> createState() => _RoomCodeStepState();
}

class _RoomCodeStepState extends State<_RoomCodeStep> {
  final _manual = TextEditingController();
  String? _error;

  void _submit(String raw) {
    final e = widget.controller.submitRoomCode(raw);
    if (mounted) setState(() => _error = e);
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanner = widget.scanner?.call(_submit) ??
        MobileScanner(onDetect: (cap) {
          final raw = cap.barcodes.firstOrNull?.rawValue;
          if (raw != null) _submit(raw);
        });
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
      _Steps(roomCheck: true, current: 0),
      const SizedBox(height: 12),
      HeroCard(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(width: 240, height: 240, child: scanner),
          ),
          const SizedBox(height: 14),
          const Text('Quét mã QR trên máy chiếu', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Mã đổi sau mỗi 30 giây, hãy quét mã đang hiện.', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.heroText)),
        ]),
      ),
      const SizedBox(height: 12),
      NeoCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Không quét được? Nhập mã dưới QR', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textLabel)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _manual,
                textCapitalization: TextCapitalization.characters,
                style: mono.copyWith(fontSize: 16, letterSpacing: 2),
                decoration: const InputDecoration(hintText: 'K7Q2 M9XA', isDense: true),
                onSubmitted: _submit,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(height: 48, child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => _submit(_manual.text), child: const Text('Xác nhận'))),
          ]),
          if (_error != null) ...[const SizedBox(height: 10), ErrorNote(_error!)],
        ]),
      ),
    ]);
  }
}

class _CameraStep extends StatefulWidget {
  const _CameraStep({required this.controller, required this.camera, required this.onCancel});
  final CheckinController controller;
  final FaceCamera camera;
  final VoidCallback onCancel;

  @override
  State<_CameraStep> createState() => _CameraStepState();
}

class _CameraStepState extends State<_CameraStep> {
  bool _ready = false;
  bool _denied = false;
  bool _capturing = false;
  final _frames = <Uint8List>[];
  String? _error;

  CheckinController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    widget.camera.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _denied = false;
      _error = null;
    });
    try {
      await widget.camera.init();
      if (mounted) setState(() => _ready = true);
    } on CameraDenied {
      if (mounted) setState(() => _denied = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Không mở được camera: $e');
    }
  }

  Future<void> _capture() async {
    setState(() {
      _capturing = true;
      _frames.clear();
    });
    try {
      for (var i = 0; i < _frameCount; i++) {
        _frames.add(await widget.camera.capture());
        if (mounted) setState(() {});
        if (i < _frameCount - 1) await Future<void>.delayed(_frameGap);
      }
      await c.submit(List.of(_frames));
    } catch (e) {
      if (mounted) setState(() => _error = 'Chụp không được: $e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_denied) return PermissionsPage(kind: PermissionKind.camera, onRetry: _open, onLater: widget.onCancel);
    final (label, icon) = _actions[c.action] ?? ('Làm theo hướng dẫn', Icons.face);
    final n = _frames.length;
    final prompt = !_capturing ? 'Bấm bắt đầu rồi làm theo' : n < 2 ? 'Nhìn thẳng vào camera…' : '$label ngay!';
    final err = _error ?? c.error;
    return Scaffold(
      backgroundColor: AppColors.hero,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Stack(children: [
              Positioned(
                top: 180, left: 0, right: 0,
                child: Center(child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30, tileMode: TileMode.decal),
                  child: Container(width: 320, height: 320, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x26F59E0B))),
                )),
              ),
              Column(children: [
                SizedBox(
                  height: 64,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      Material(
                        color: const Color(0x14FFFFFF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0x1AFFFFFF))),
                        child: InkWell(borderRadius: BorderRadius.circular(16), onTap: widget.onCancel,
                            child: const SizedBox.square(dimension: 40, child: Icon(Icons.arrow_back, size: 20, color: Colors.white))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('BƯỚC ${c.roomCheck ? 3 : 2}/${c.roomCheck ? 3 : 2}',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: Color(0xFFA5B4FC))),
                          const Text('Thử thách khuôn mặt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                        ]),
                      ),
                      Pill('${(c.secondsLeft ~/ 60).toString().padLeft(2, '0')}:${(c.secondsLeft % 60).toString().padLeft(2, '0')}',
                          icon: Icons.hourglass_top, bg: const Color(0x26F59E0B), fg: const Color(0xFFFCD34D),
                          border: const Color(0x59F59E0B), monospace: true, fontSize: 13,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5)),
                    ]),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22),
                      boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 40, offset: Offset(0, 16))]),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFDE68A))),
                      child: Icon(icon, size: 26, color: const Color(0xFFB45309)),
                    ),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Nhìn thẳng, rồi', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                      Text(label, style: const TextStyle(fontSize: 19, height: 24 / 19, fontWeight: FontWeight.w800, color: AppColors.text)),
                    ]),
                  ]),
                ),
                Expanded(
                  child: Center(
                    child: Container(
                      width: 250, height: 320,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.all(Radius.elliptical(125, 160)),
                        border: Border.all(color: const Color(0xFF34D399), width: 4),
                        color: const Color(0xFF111A2E),
                        boxShadow: const [BoxShadow(color: Color(0x4D34D399), blurRadius: 44)],
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.all(Radius.elliptical(121, 156)),
                        child: _ready
                            ? FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge,
                                child: SizedBox(width: 250, height: 320, child: widget.camera.preview()))
                            : const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0x0FFFFFFF), borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0x1AFFFFFF))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(prompt, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Khung hình đã chụp', style: TextStyle(fontSize: 12, color: AppColors.heroText)),
                      Text('$n/$_frameCount', style: mono.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF6EE7B7))),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      for (var i = 0; i < _frameCount; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(child: Container(height: 6, decoration: BoxDecoration(
                            color: i < n ? const Color(0xFF34D399) : const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(3)))),
                      ],
                    ]),
                    if (err != null) ...[const SizedBox(height: 12), ErrorNote(err)],
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF020617), elevation: 0),
                        onPressed: _ready && !_capturing ? _capture : null,
                        icon: const Icon(Icons.play_arrow, color: AppColors.primary),
                        label: Text(_capturing ? 'Đang chụp…' : 'Bắt đầu'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Color(0x1FFFFFFF)),
                            backgroundColor: const Color(0x14FFFFFF), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        onPressed: widget.onCancel,
                        child: const Text('Hủy lượt này', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ResultStep extends StatelessWidget {
  const _ResultStep({required this.controller, required this.classCode, required this.className, required this.onHome,
      required this.onEnroll});
  final CheckinController controller;
  final String classCode;
  final String className;
  final VoidCallback onHome;
  final VoidCallback onEnroll;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final kind = c.finalCode == 'ALREADY_PRESENT' ? 'pass' : c.result ?? 'fail';
    final left = c.attemptsLeft ?? 0;
    final (glow, tileBg, tileFg, icon, status, title, body) = switch (kind) {
      'pass' => (const Color(0x5910B981), const Color(0x3310B981), const Color(0xFF34D399), Icons.check_circle, 'Có mặt',
          'Đã điểm danh', c.finalCode == 'ALREADY_PRESENT' ? 'Bạn đã được ghi nhận có mặt ở buổi học này rồi.' : 'Bạn được ghi nhận có mặt ở buổi học này.'),
      'suspicious' => (const Color(0x4DF59E0B), const Color(0x33F59E0B), const Color(0xFFFBBF24), Icons.hourglass_top,
          'Chờ xác nhận', 'Đang chờ giảng viên', 'Lượt điểm danh đã gửi. Giảng viên sẽ xác nhận trong buổi, bạn không cần thử lại.'),
      _ => (const Color(0x4DF43F5E), const Color(0x33F43F5E), const Color(0xFFFB7185), Icons.cancel, 'Không đạt',
          'Chưa điểm danh được', c.finalCode == null && left > 0 ? 'Đừng lo, bạn vẫn còn lượt thử trong phiên này.'
              : (c.finalCode == null ? 'Bạn đã dùng hết lượt. Hãy báo giảng viên để được điểm danh tay.' : '')),
    };
    final when = c.submittedAt ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final canRetry = kind == 'fail' && c.finalCode == null && left > 0;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 20), children: [
      HeroCard(
        glow: glow,
        emeraldGlow: false,
        padding: const EdgeInsets.fromLTRB(20, 36, 20, 28),
        child: Column(children: [
          Container(width: 92, height: 92, decoration: BoxDecoration(color: tileBg, borderRadius: BorderRadius.circular(30),
              border: Border.all(color: tileFg.withValues(alpha: 0.4))), child: Icon(icon, size: 52, color: tileFg)),
          const SizedBox(height: 14),
          Pill(status.toUpperCase(), bg: tileBg, fg: tileFg, border: tileFg.withValues(alpha: 0.3)),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, height: 32 / 26, fontWeight: FontWeight.w800)),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 20 / 14, color: AppColors.heroText)),
          ],
        ]),
      ),
      if (kind == 'fail' && c.reasonMessage != null) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.absentSoft, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.absentBorder)),
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Icon(_actions[c.action]?.$2 ?? Icons.info_outline, size: 22, color: AppColors.absentText)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('LÝ DO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: Color(0xFF9F1239))),
                Text(c.reasonMessage!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF881337))),
              ]),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 14),
      NeoCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(children: [
          if (classCode.isNotEmpty)
            _row('Lớp', Row(mainAxisSize: MainAxisSize.min, children: [CodeChip(classCode), const SizedBox(width: 6),
              Text(className, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))])),
          _row('Thời điểm', Text('${two(when.hour)}:${two(when.minute)} · ${two(when.day)}/${two(when.month)}/${when.year}',
              style: mono.copyWith(fontSize: 13, fontWeight: FontWeight.w600)), last: kind != 'fail' && c.finalCode != null),
          if (kind == 'fail' && c.finalCode == null)
            _row('Lượt còn lại', Pill('$left/5', bg: AppColors.primarySoft, fg: const Color(0xFF4338CA), border: const Color(0xFFE0E7FF), fontSize: 12), last: true)
          else if (c.finalCode == null)
            _row('Trạng thái', Pill(kind == 'pass' ? 'Có mặt' : 'Chờ duyệt',
                bg: kind == 'pass' ? AppColors.presentSoft : const Color(0xFFFFFBEB),
                fg: kind == 'pass' ? AppColors.presentText : const Color(0xFF92400E),
                border: kind == 'pass' ? AppColors.presentBorder : const Color(0xFFFDE68A), fontSize: 12), last: true),
        ]),
      ),
      const SizedBox(height: 20),
      if (canRetry) ...[
        FilledButton.icon(onPressed: c.retry, icon: const Icon(Icons.refresh, size: 18), label: const Text('Thử lại')),
        const SizedBox(height: 10),
      ],
      if (c.finalCode == 'FACE_NOT_ENROLLED') ...[
        FilledButton.icon(onPressed: onEnroll, icon: const Icon(Icons.face_retouching_natural, size: 18), label: const Text('Đăng ký khuôn mặt')),
        const SizedBox(height: 10),
      ],
      SizedBox(
        height: 52,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.text, side: const BorderSide(color: AppColors.inputBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          onPressed: onHome,
          child: const Text('Về trang chủ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ),
    ]);
  }

  static Widget _row(String label, Widget value, {bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.cardBorder))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          value,
        ]),
      );
}
