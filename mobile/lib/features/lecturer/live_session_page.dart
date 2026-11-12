import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import '../student/request_sheet.dart' show absencePill;
import 'open_session_page.dart' show Segmented;

const pollEvery = Duration(seconds: 4); // đặc tả 4.5: 3–5 giây

/// Nhãn, biểu tượng và màu (nền, chữ, viền) của trạng thái kết quả.
const statusStyle = <String, (String, IconData, Color, Color, Color)>{
  'present': ('Có mặt', Icons.check_circle, AppColors.presentSoft, AppColors.presentText, AppColors.presentBorder),
  'manual_present': ('Duyệt có mặt', Icons.check_circle, AppColors.presentSoft, AppColors.presentText, AppColors.presentBorder),
  'suspicious': ('Đáng ngờ', Icons.flag, Color(0xFFFFFBEB), Color(0xFF92400E), Color(0xFFFDE68A)),
  'excused': ('Vắng có phép', Icons.description, Color(0xFFF1F5F9), AppColors.textLabel, AppColors.inputBorder),
  'absent': ('Chưa điểm danh', Icons.schedule, Color(0xFFF1F5F9), AppColors.textSecondary, AppColors.inputBorder),
  'rejected': ('Từ chối', Icons.cancel, AppColors.absentSoft, AppColors.absentText, AppColors.absentBorder),
};

/// Cờ của lượt → (lý do ngắn, biểu tượng).
(String, IconData) flagText(String flag, Map? attempt) => switch (flag) {
      'LOCATION_DRIFT' => ('Lệch vị trí ${(attempt?['distance_m'] as num?)?.round() ?? ''} m', Icons.share_location),
      'FACE_BORDERLINE' => ('Khuôn mặt sát ngưỡng', Icons.face),
      'MOCK_LOCATION' => ('Nghi vị trí giả', Icons.location_off),
      'LOCATION_JUMP' => ('Vị trí nhảy bất thường', Icons.moving),
      'SHARED_DEVICE' => ('Dùng chung máy', Icons.devices),
      'ROOM_TOKEN_BURST' => ('Nhiều lượt cùng mạng', Icons.wifi),
      _ => (flag, Icons.flag),
    };

const failText = {
  'ROOM_TOKEN_INVALID': 'Sai mã phòng',
  'GPS_ACCURACY_LOW': 'GPS kém',
  'GPS_TOO_FAR': 'Ở xa lớp',
  'FACE_NOT_ENROLLED': 'Chưa đăng ký mặt',
  'ACTION_NOT_DETECTED': 'Sai hành động',
  'SPOOF_SUSPECTED': 'Nghi giả mạo',
  'FACE_MISMATCH': 'Không khớp mặt',
};

/// Dòng lý do dưới tên sinh viên: cờ đầu tiên của lượt đáng ngờ, lý do lượt hỏng, hoặc trạng thái.
(String, IconData, Color, Color, Color) reasonOf(Map r) {
  final a = r['last_attempt'] as Map?;
  final status = '${r['status']}';
  final flags = (a?['flags'] as List?)?.cast<String>() ?? const [];
  final (label, icon, bg, fg, border) = statusStyle[status] ?? statusStyle['absent']!;
  if (status == 'suspicious' && flags.isNotEmpty) {
    final (t, i) = flagText(flags.first, a);
    return (flags.length > 1 ? '$t +${flags.length - 1}' : t, i, bg, fg, border);
  }
  if (status == 'absent' && a != null && a['result'] == 'fail') {
    return ('${failText[a['fail_reason']] ?? 'Lượt không đạt'} · ${r['attempt_count']} lượt', Icons.error_outline,
        AppColors.absentSoft, AppColors.absentText, AppColors.absentBorder);
  }
  return (label, icon, bg, fg, border);
}

String hhmm(Object? iso) {
  if (iso == null) return '';
  final d = DateTime.parse('$iso').toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

const avatarColors = [
  (Color(0xFFEEF2FF), Color(0xFF4338CA)),
  (Color(0xFFECFDF5), Color(0xFF047857)),
  (Color(0xFFF5F3FF), Color(0xFF6D28D9)),
  (Color(0xFFFFFBEB), Color(0xFFB45309)),
  (Color(0xFFFFF1F2), Color(0xFFE11D48)),
];

/// Artboard "GV · Phiên đang chạy" (GV_PhienDangChay.dc.html). GET /sessions/{id}/records mỗi 4 s khi phiên mở.
class LiveSessionPage extends StatefulWidget {
  const LiveSessionPage({super.key, required this.session, required this.sessionId});
  final Session session;
  final int sessionId;

  @override
  State<LiveSessionPage> createState() => _LiveSessionPageState();
}

class _LiveSessionPageState extends State<LiveSessionPage> {
  Map<String, dynamic>? _data;
  String? _error;
  int _filter = 1; // 0 tất cả, 1 đáng ngờ, 2 chưa
  bool _picking = false; // chế độ chọn nhiều để điểm danh hàng loạt
  final _picked = <int>{};
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(pollEvery, (_) {
      if (_data?['session']['is_open'] == true) _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await widget.session.api.get('/sessions/${widget.sessionId}/records') as Map;
      if (mounted) {
        setState(() {
          _data = Map<String, dynamic>.from(r);
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _act(Future<Object?> Function() f, String done) async {
    setState(() => _busy = true);
    try {
      await f();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done), behavior: SnackBarBehavior.floating));
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Đóng phiên điểm danh?'),
        content: const Text('Sinh viên sẽ không điểm danh được nữa. Bạn vẫn sửa được kết quả sau khi đóng.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
          FilledButton(style: dialogButtonStyle, onPressed: () => Navigator.pop(c, true), child: const Text('Đóng phiên')),
        ],
      ),
    );
    if (ok == true) await _act(() => widget.session.api.post('/sessions/${widget.sessionId}/close'), 'Đã đóng phiên');
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final s = d?['session'] as Map?;
    final open = s?['is_open'] == true;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(children: [
              NeoHeader(
                label: s == null ? '' : '${s['class']['code']} · MỞ ${hhmm(s['opened_at'])}',
                title: s == null ? 'Phiên điểm danh' : '${s['class']['name']}',
                onBack: () => context.canPop() ? context.pop() : context.go('/lecturer'),
                trailing: [
                  if (open && s!['room_check'] == true)
                    HeaderTile(
                      tooltip: 'Chiếu mã phòng',
                      onTap: () => context.push('/lecturer/session/${widget.sessionId}/room'),
                      child: const Icon(Icons.qr_code_2, size: 20, color: AppColors.textSecondary),
                    ),
                  if (open)
                    SizedBox(
                      height: 40,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppColors.absentSoft, foregroundColor: AppColors.absentText,
                          side: const BorderSide(color: AppColors.absentBorder), padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        onPressed: _busy ? null : _close,
                        icon: const Icon(Icons.stop_circle_outlined, size: 17),
                        label: const Text('Đóng'),
                      ),
                    )
                  else if (s != null)
                    Pill('Đã đóng', bg: const Color(0xFFF1F5F9), fg: AppColors.textSecondary, border: AppColors.inputBorder,
                        icon: Icons.lock_outline),
                ],
              ),
              Expanded(child: d == null ? LoadingOrError(error: _error, onRetry: _load) : _body(d)),
              if (_picking) _bulkBar(),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final s = d['session'] as Map;
    final counts = Map<String, int>.from(d['counts'] as Map);
    final records = [for (final r in d['records'] as List) Map<String, dynamic>.from(r as Map)];
    final present = counts['present']! + counts['manual_present']!;
    final shown = switch (_filter) {
      1 => records.where((r) => r['status'] == 'suspicious'),
      2 => records.where((r) => r['status'] == 'absent'),
      _ => records,
    }.toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        HeroCard(
          emeraldGlow: false,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              s['is_open'] == true
                  ? const LivePill('Trực tiếp')
                  : Pill('ĐÃ ĐÓNG ${hhmm(s['closed_at'] ?? s['expires_at'])}', bg: const Color(0x14FFFFFF),
                      fg: AppColors.heroText, border: const Color(0x1FFFFFFF)),
              if (s['is_open'] == true) CountdownPill(until: DateTime.parse('${s['expires_at']}').toLocal()),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _Stat('$present', 'Có mặt', const Color(0xFF34D399)),
              const SizedBox(width: 8),
              _Stat('${counts['suspicious']}', 'Đáng ngờ', const Color(0xFFFBBF24)),
              const SizedBox(width: 8),
              _Stat('${counts['absent']}', 'Chưa', const Color(0xFFE2E8F0)),
            ]),
          ]),
        ),
        if (s['recenter_suggested'] == true && s['is_open'] == true) ...[
          const SizedBox(height: 12),
          _RecenterBanner(
            records: records,
            busy: _busy,
            onRecenter: () => _act(() => widget.session.api.post('/sessions/${widget.sessionId}/recenter'), 'Đã tính lại tâm phiên'),
          ),
        ],
        if (_error != null) ...[const SizedBox(height: 12), ErrorNote(_error!)],
        const SizedBox(height: 12),
        Segmented(
          dark: true,
          background: Colors.white,
          options: ['Tất cả', 'Đáng ngờ · ${counts['suspicious']}', 'Chưa · ${counts['absent']}'],
          selected: _filter,
          onChanged: (i) => setState(() => _filter = i),
        ),
        const SizedBox(height: 8),
        Row(children: [
          if (_picking) ...[
            TextButton(
              onPressed: () => setState(() => shown.every((r) => _picked.contains(r['student_id']))
                  ? _picked.removeAll(shown.map((r) => r['student_id']))
                  : _picked.addAll(shown.map((r) => r['student_id'] as int))),
              child: Text(shown.isNotEmpty && shown.every((r) => _picked.contains(r['student_id']))
                  ? 'Bỏ chọn cả mục này' : 'Chọn cả ${shown.length} người'),
            ),
          ] else
            const Expanded(
              child: Text('Mất mạng, GPS phòng hỏng?', overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
          if (_picking) const Spacer(),
          TextButton.icon(
            onPressed: () => setState(() {
              _picking = !_picking;
              _picked.clear();
            }),
            icon: Icon(_picking ? Icons.close : Icons.checklist, size: 18),
            label: Text(_picking ? 'Thôi chọn' : 'Điểm danh hàng loạt'),
          ),
        ]),
        const SizedBox(height: 4),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Không có sinh viên nào ở mục này.', textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted)),
          ),
        for (final (i, r) in shown.indexed) ...[
          _Row(r, colors: avatarColors[i % avatarColors.length], picked: _picking ? _picked.contains(r['student_id']) : null,
              onTap: _picking
                  ? () => setState(() => _picked.contains(r['student_id'])
                      ? _picked.remove(r['student_id'])
                      : _picked.add(r['student_id'] as int))
                  : () async {
                      await context.push('/lecturer/session/${widget.sessionId}/student/${r['student_id']}');
                      _load();
                    }),
          const SizedBox(height: 10),
        ],
      ]),
    );
  }

  /// Thanh dưới khi chọn nhiều: đặt cùng trạng thái cho mọi người đã chọn (PATCH /sessions/{id}/records).
  Widget _bulkBar() {
    final n = _picked.length;
    Widget btn(String label, String status, Color fg, Color bg) => Expanded(
          child: SizedBox(
            height: 44,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: bg, foregroundColor: fg, elevation: 0, minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: n == 0 || _busy ? null : () => _bulk(status, label),
              child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.cardBorder)),
          boxShadow: [BoxShadow(color: Color(0x140F172A), blurRadius: 20, offset: Offset(0, -4))]),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(n == 0 ? 'Chạm vào sinh viên để chọn' : 'Đã chọn $n sinh viên, đặt thành:',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textLabel)),
        const SizedBox(height: 8),
        Row(children: [
          btn('Có mặt', 'manual_present', Colors.white, AppColors.present),
          const SizedBox(width: 6),
          btn('Có phép', 'excused', AppColors.textLabel, const Color(0xFFF1F5F9)),
          const SizedBox(width: 6),
          btn('Vắng', 'absent', AppColors.absentText, AppColors.absentSoft),
        ]),
      ]),
    );
  }

  Future<void> _bulk(String status, String label) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Đặt "$label" cho ${_picked.length} sinh viên?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Kết quả bị khóa như duyệt tay; mỗi người được ghi vào nhật ký.'),
          const SizedBox(height: 12),
          TextField(controller: note, maxLength: 500,
              decoration: const InputDecoration(labelText: 'Ghi chú (vd: mất mạng, điểm danh tay)', counterText: '')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
          FilledButton(style: dialogButtonStyle, onPressed: () => Navigator.pop(c, true), child: const Text('Xác nhận')),
        ],
      ),
    );
    if (ok != true) return;
    final ids = _picked.toList();
    await _act(() => widget.session.api.patch('/sessions/${widget.sessionId}/records',
        data: {'student_ids': ids, 'status': status, 'note': note.text.trim().isEmpty ? null : note.text.trim()}),
        'Đã đặt "$label" cho ${ids.length} sinh viên');
    if (mounted) {
      setState(() {
        _picking = false;
        _picked.clear();
      });
    }
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x0FFFFFFF))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: mono.copyWith(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.heroText)),
          ]),
        ),
      );
}

class _RecenterBanner extends StatelessWidget {
  const _RecenterBanner({required this.records, required this.busy, required this.onRecenter});
  final List<Map<String, dynamic>> records;
  final bool busy;
  final VoidCallback onRecenter;

  @override
  Widget build(BuildContext context) {
    final drift = records.where((r) => ((r['last_attempt'] as Map?)?['flags'] as List?)?.contains('LOCATION_DRIFT') == true);
    final dists = [for (final r in drift) ((r['last_attempt'] as Map)['distance_m'] as num).toDouble()]..sort();
    final median = dists.isEmpty ? null : dists[dists.length ~/ 2];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFDE68A))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.explore, size: 20, color: Color(0xFFB45309)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(style: const TextStyle(fontSize: 13, height: 18 / 13, color: Color(0xFF78350F)), children: [
              const TextSpan(text: 'Tâm phiên có thể lệch. ', style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: median == null
                  ? 'Nhiều sinh viên đã qua khuôn mặt cùng lệch một phía.'
                  : '${math.max(dists.length, 5)} sinh viên đã qua khuôn mặt cùng lệch ~${median.round()} m một phía.'),
            ])),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB45309), elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 34),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700)),
                onPressed: busy ? null : onRecenter,
                icon: const Icon(Icons.my_location, size: 16),
                label: const Text('Tính lại tâm'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.r, {required this.colors, required this.onTap, this.picked});

  /// null: không ở chế độ chọn; true/false: ô đánh dấu.
  final bool? picked;
  final Map<String, dynamic> r;
  final (Color, Color) colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (text, icon, bg, fg, border) = reasonOf(r);
    return NeoCard(
      radius: 20,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            InitialsAvatar('${r['full_name']}', bg: colors.$1, fg: colors.$2, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text('${r['full_name']}', overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text))),
                  const SizedBox(width: 6),
                  Pill('${r['student_code']}', bg: const Color(0xFFF1F5F9), fg: AppColors.textSecondary, radius: 5,
                      monospace: true, fontSize: 10, padding: const EdgeInsets.symmetric(horizontal: 5)),
                ]),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  Pill(text, icon: icon, bg: bg, fg: fg, border: border, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
                  if (r['warn'] == true) absencePill(r['absences'] as int), // vắng nhiều ở lớp này (buổi đã đóng)
                ]),
              ]),
            ),
            if (picked == null)
              const Icon(Icons.chevron_right, size: 20, color: Color(0xFF94A3B8))
            else
              Checkbox(value: picked, onChanged: (_) => onTap()),
          ]),
        ),
      ),
    );
  }
}
