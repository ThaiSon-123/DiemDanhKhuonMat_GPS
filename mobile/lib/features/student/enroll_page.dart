import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/capture.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import 'face_reasons.dart';
import 'permissions_page.dart';

const _steps = [
  ('Thẳng', 'Nhìn thẳng vào camera'),
  ('Quay trái', 'Hơi quay mặt sang trái'),
  ('Quay phải', 'Hơi quay mặt sang phải'),
];

/// Hướng mặt cần cho từng bước (khớp `pose` của POST /faces/precheck).
const _poses = ['front', 'left', 'right'];
const _autoEvery = Duration(milliseconds: 700);
const _autoNeed = 2; // số khung đạt liên tiếp trước khi giữ ảnh

/// Artboard "SV · Đăng ký khuôn mặt" (SV_DangKyKhuonMat.dc.html). Chụp 3 ảnh rồi POST /faces/enroll.
/// Tự chụp: mỗi ~0,7 s gửi một khung lên POST /faces/precheck (server phát hiện mặt, đo sáng, nét, hướng mặt;
/// không lưu ảnh); đủ 2 khung đạt liên tiếp đúng hướng thì giữ ảnh và sang bước sau. Vẫn có nút chụp tay.
/// Server kiểm tra lại cả 3 ảnh khi gửi và trả lý do để chụp lại đúng ảnh hỏng.
class EnrollPage extends StatefulWidget {
  const EnrollPage({super.key, required this.session, this.camera, this.autoCapture = true});
  final Session session;
  final FaceCamera? camera;
  final bool autoCapture;

  @override
  State<EnrollPage> createState() => _EnrollPageState();
}

class _EnrollPageState extends State<EnrollPage> {
  late final FaceCamera _cam = widget.camera ?? DeviceCamera();
  final _shots = List<Uint8List?>.filled(_steps.length, null);
  Map<int, String> _issues = {};
  int _step = 0;
  bool _ready = false;
  bool _denied = false;
  bool _busy = false;
  String? _error;
  late bool _auto = widget.autoCapture;
  Timer? _autoTimer;
  bool _checking = false;
  int _streak = 0;
  String? _hint; // gợi ý tự chụp: "Quay thêm sang trái", lý do chưa đạt…

  @override
  void initState() {
    super.initState();
    _open();
    _autoTimer = Timer.periodic(_autoEvery, (_) => _autoTick());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _cam.dispose();
    super.dispose();
  }

  bool get _needShot => _shots[_step] == null || _issues.containsKey(_step);

  Future<void> _autoTick() async {
    if (!_auto || !_ready || _busy || _checking || !_needShot || !mounted) return;
    _checking = true;
    final step = _step;
    try {
      final img = await _cam.capture();
      final r = await widget.session.api.post('/faces/precheck', data: FormData.fromMap({
        'photo': MultipartFile.fromBytes(img, filename: 'f.jpg', contentType: DioMediaType('image', 'jpeg')),
      }));
      if (!mounted || step != _step || !_auto) return;
      final ok = r is Map && r['ok'] == true;
      final pose = r is Map ? r['pose'] as String? : null;
      if (ok && pose == _poses[step]) {
        _streak++;
        if (_streak >= _autoNeed) {
          _streak = 0;
          _keep(img);
          setState(() => _hint = null);
          return;
        }
        setState(() => _hint = 'Giữ yên…');
      } else {
        _streak = 0;
        setState(() => _hint = !ok
            ? (r is Map && r['reason'] != null ? faceReason('${r['reason']}') : null)
            : switch ((_poses[step], pose)) {
                ('front', _) => 'Nhìn thẳng vào camera',
                ('left', 'right') => 'Quay sang trái của bạn (đang quay phải)',
                ('right', 'left') => 'Quay sang phải của bạn (đang quay trái)',
                ('left', _) => 'Quay thêm sang trái',
                _ => 'Quay thêm sang phải',
              });
      }
    } catch (_) {
      // Mạng chập chờn hoặc server chưa có /faces/precheck: bỏ qua lượt này, vẫn chụp tay được.
    } finally {
      _checking = false;
    }
  }

  void _keep(Uint8List img) => setState(() {
        _shots[_step] = img;
        _issues.remove(_step);
        final next = List.generate(_steps.length, (i) => i).where((i) => _shots[i] == null || _issues.containsKey(i));
        if (next.isNotEmpty) _step = next.first;
      });

  Future<void> _open() async {
    setState(() {
      _denied = false;
      _error = null;
    });
    try {
      await _cam.init();
      if (mounted) setState(() => _ready = true);
    } on CameraDenied {
      if (mounted) setState(() => _denied = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Không mở được camera: $e');
    }
  }

  bool get _allTaken => _shots.every((s) => s != null);

  Future<void> _take() async {
    setState(() => _busy = true);
    try {
      _keep(await _cam.capture());
    } catch (e) {
      setState(() => _error = 'Chụp không được: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.api.get('/me'); // làm mới token trước: FormData không gửi lại được nếu phải refresh giữa chừng
      final form = FormData.fromMap({
        'photos': [
          for (final (i, s) in _shots.indexed) MultipartFile.fromBytes(s!, filename: '$i.jpg', contentType: DioMediaType('image', 'jpeg')),
        ],
      });
      await widget.session.api.post('/faces/enroll', data: form);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Đã gửi ảnh. Khuôn mặt của bạn đang chờ duyệt.'), behavior: SnackBarBehavior.floating));
      context.go('/student/face');
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code == 'ENROLL_REJECTED' && e.details is Map) {
        final list = (e.details as Map)['photos'] as List? ?? const [];
        setState(() {
          _issues = {for (final p in list) (p as Map)['index'] as int: '${p['reason']}'};
          _step = _issues.keys.isEmpty ? 0 : (_issues.keys.toList()..sort()).first;
        });
      } else if (e.code == 'CONSENT_REQUIRED') {
        context.go('/student/consent');
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_denied) {
      return PermissionsPage(kind: PermissionKind.camera, onRetry: _open, onLater: () => context.go('/student'));
    }
    final total = _steps.length;
    final done = _shots.where((s) => s != null).length;
    final (_, instruction) = _steps[_step];
    return Scaffold(
      backgroundColor: AppColors.hero,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Stack(children: [
              Positioned(
                top: 120,
                left: 0,
                right: 0,
                child: Center(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30, tileMode: TileMode.decal),
                    child: Container(width: 300, height: 300, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x404F46E5))),
                  ),
                ),
              ),
              Column(children: [
                _header(done, total),
                Expanded(child: _viewfinder()),
                _panel(instruction),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header(int done, int total) => SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Material(
              color: const Color(0x14FFFFFF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0x1AFFFFFF))),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.go('/student'),
                child: const SizedBox.square(dimension: 40, child: Icon(Icons.arrow_back, size: 20, color: Colors.white)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('ĐĂNG KÝ KHUÔN MẶT',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: Color(0xFFA5B4FC))),
                Text(_allTaken && _issues.isEmpty ? 'Kiểm tra và gửi ảnh' : 'Ảnh ${_step + 1} trên $total',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
            Pill('$done/$total', bg: const Color(0x336366F1), fg: const Color(0xFFC7D2FE), border: const Color(0x4D818CF8),
                monospace: true, fontSize: 12, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
          ]),
        ),
      );

  Widget _viewfinder() {
    final shot = _shots[_step];
    final retake = _issues.containsKey(_step);
    final border = retake ? AppColors.absent : const Color(0xFF34D399);
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Pill(
        retake
            ? 'Ảnh ${_step + 1}: ${faceReason(_issues[_step]!)}'
            : !_ready
                ? 'Đang mở camera…'
                : _auto && _needShot
                    ? (_hint ?? 'Đưa mặt vào khung, máy sẽ tự chụp')
                    : 'Đưa mặt vào khung rồi bấm chụp',
        bg: retake ? const Color(0x26F43F5E) : const Color(0x2610B981),
        fg: retake ? const Color(0xFFFDA4AF) : const Color(0xFF6EE7B7),
        border: retake ? const Color(0x59F43F5E) : const Color(0x5910B981),
        dot: true,
        fontSize: 12,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      ),
      const SizedBox(height: 18),
      Container(
        width: 236,
        height: 300,
        decoration: BoxDecoration(
          shape: BoxShape.rectangle,
          borderRadius: const BorderRadius.all(Radius.elliptical(118, 150)),
          border: Border.all(color: border, width: 3),
          color: const Color(0xFF111A2E),
          boxShadow: [BoxShadow(color: border.withValues(alpha: 0.25), blurRadius: 40)],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.elliptical(115, 147)),
          child: _error != null && !_ready
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.heroText))))
              : FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: 236, height: 300,
                  child: shot != null && !retake && !_allTaken ? Image.memory(shot, fit: BoxFit.cover) : _cam.preview())),
        ),
      ),
    ]);
  }

  Widget _panel(String instruction) {
    final ready = _allTaken && _issues.isEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0x0FFFFFFF),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0x1AFFFFFF)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              for (final (i, (label, _)) in _steps.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _stepChip(i, label)),
              ],
            ]),
            const SizedBox(height: 14),
            Text(ready ? 'Đã đủ 3 ảnh' : instruction,
                style: const TextStyle(fontSize: 20, height: 26 / 20, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 4),
            Text(
                ready
                    ? 'Bấm vào từng ảnh ở trên để chụp lại nếu cần, rồi gửi để giảng viên duyệt.'
                    : 'Giữ khuôn mặt trong khung oval: một người, đủ sáng, giữ máy chắc tay.',
                style: const TextStyle(fontSize: 13, height: 19 / 13, color: AppColors.heroText)),
            if (_issues.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final e in (_issues.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
                Text('Ảnh ${e.key + 1}: ${faceReason(e.value)}',
                    style: const TextStyle(fontSize: 13, height: 19 / 13, color: Color(0xFFFDA4AF))),
            ],
            if (_error != null && _ready) ...[const SizedBox(height: 10), ErrorNote(_error!)],
            if (!ready) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFA5B4FC)),
                const SizedBox(width: 6),
                const Expanded(child: Text('Tự chụp khi mặt đạt yêu cầu', style: TextStyle(fontSize: 13, color: AppColors.heroText))),
                Switch(
                  value: _auto,
                  onChanged: (v) => setState(() {
                    _auto = v;
                    _streak = 0;
                    _hint = null;
                  }),
                ),
              ]),
            ],
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF020617), elevation: 0),
                onPressed: !_ready || _busy ? null : (ready ? _send : _take),
                icon: Icon(ready ? Icons.send : Icons.photo_camera, size: 20, color: AppColors.primary),
                label: Text(_busy ? 'Đang xử lý…' : ready ? 'Gửi ảnh để duyệt' : _auto ? 'Chụp ngay ảnh ${_step + 1}' : 'Chụp ảnh ${_step + 1}'),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x59000000),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x0FFFFFFF)),
              ),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.lock_outline, size: 16, color: Color(0xFFA5B4FC)),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Ảnh chỉ để đối chiếu với thẻ sinh viên và bị xóa ngay sau khi duyệt.',
                      style: TextStyle(fontSize: 12, height: 17 / 12, color: AppColors.heroText)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _stepChip(int i, String label) {
    final taken = _shots[i] != null;
    final bad = _issues.containsKey(i);
    final current = i == _step && !(_allTaken && _issues.isEmpty);
    final (bg, fg, border) = bad
        ? (const Color(0x26F43F5E), const Color(0xFFFDA4AF), const Color(0x4DF43F5E))
        : current
            ? (Colors.white, AppColors.hero, Colors.white)
            : taken
                ? (const Color(0x2610B981), const Color(0xFF6EE7B7), const Color(0x4D10B981))
                : (const Color(0x0AFFFFFF), const Color(0xFF94A3B8), const Color(0x14FFFFFF));
    return Semantics(
      button: true,
      label: '$label${bad ? ', cần chụp lại' : taken ? ', đã chụp' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _step = i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (taken && !bad && !current) ...[Icon(Icons.check, size: 14, color: fg), const SizedBox(width: 4)],
            if (bad) ...[Icon(Icons.refresh, size: 14, color: fg), const SizedBox(width: 4)],
            Text(label, style: TextStyle(fontSize: 12, fontWeight: current ? FontWeight.w700 : FontWeight.w600, color: fg)),
          ]),
        ),
      ),
    );
  }
}
