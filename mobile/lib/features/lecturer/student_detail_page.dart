import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import 'live_session_page.dart';

const _decisions = [
  ('manual_present', 'Có mặt', Icons.check_circle),
  ('excused', 'Vắng có phép', null),
  ('absent', 'Vắng', null),
  ('rejected', 'Từ chối lượt', null),
];

/// Artboard "GV · Chi tiết sinh viên" (GV_ChiTietSV.dc.html). GET /sessions/{id}/records/{student_id},
/// GET /attempts/{id}/evidence, PATCH /sessions/{id}/records/{student_id}.
class StudentDetailPage extends StatefulWidget {
  const StudentDetailPage({super.key, required this.session, required this.sessionId, required this.studentId});
  final Session session;
  final int sessionId;
  final int studentId;

  @override
  State<StudentDetailPage> createState() => _StudentDetailPageState();
}

class _StudentDetailPageState extends State<StudentDetailPage> {
  Map<String, dynamic>? _data;
  Uint8List? _evidence;
  String? _error;
  String? _choice;
  final _note = TextEditingController();
  bool _saving = false;

  String get _base => '/sessions/${widget.sessionId}/records/${widget.studentId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = Map<String, dynamic>.from(await widget.session.api.get(_base) as Map);
      final rec = d['record'] as Map;
      setState(() {
        _data = d;
        _note.text = '${rec['note'] ?? ''}';
        _choice = _decisions.any((x) => x.$1 == rec['status']) && rec['decided_by'] != null ? '${rec['status']}' : null;
      });
      final withEvidence = (d['attempts'] as List).cast<Map>().where((a) => a['has_evidence'] == true).firstOrNull;
      if (withEvidence != null) {
        final b = await widget.session.api.getBytes('/attempts/${withEvidence['id']}/evidence');
        if (mounted) setState(() => _evidence = b);
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.session.api.patch(_base, data: {'status': _choice, 'note': _note.text.trim().isEmpty ? null : _note.text.trim()});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã lưu quyết định'), behavior: SnackBarBehavior.floating));
        context.canPop() ? context.pop(true) : _load();
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final rec = d?['record'] as Map?;
    final attempts = (d?['attempts'] as List?)?.cast<Map>() ?? const [];
    final last = attempts.firstOrNull;
    final style = statusStyle['${rec?['status']}'];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(children: [
              NeoHeader(
                label: rec == null ? '' : [
                  '${rec['student_code']}',
                  if (last != null) 'LƯỢT ${attempts.length}',
                  if (last != null) hhmm(last['received_at']),
                ].join(' · '),
                title: '${rec?['full_name'] ?? 'Sinh viên'}',
                onBack: () => context.canPop() ? context.pop() : context.go('/lecturer'),
                trailing: [
                  if (style != null)
                    Pill(style.$1, icon: style.$2, bg: style.$3, fg: style.$4, border: style.$5),
                ],
              ),
              Expanded(
                child: d == null
                    ? LoadingOrError(error: _error, onRetry: _load)
                    : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 20), children: [
                        if (last != null) ...[
                          _EvidenceCard(attempt: last, image: _evidence),
                          const SizedBox(height: 12),
                          if (last['distance_m'] != null) ...[_DistanceCard(last), const SizedBox(height: 12)],
                        ] else
                          const NeoCard(
                            child: Text('Sinh viên chưa gửi lượt điểm danh nào trong phiên này.',
                                style: TextStyle(color: AppColors.textMuted)),
                          ),
                        const SizedBox(height: 4),
                        const Text('Quyết định của bạn',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
                        const SizedBox(height: 8),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 3.4,
                          children: [for (final x in _decisions) _decisionButton(x)],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _note,
                          maxLines: 2,
                          maxLength: 500,
                          decoration: const InputDecoration(hintText: 'Ghi chú (vd: đã thấy SV ngồi bàn cuối)', counterText: ''),
                        ),
                        if (_error != null) ...[const SizedBox(height: 10), ErrorNote(_error!)],
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 52,
                          child: FilledButton(onPressed: _choice != null && !_saving ? _save : null,
                              child: Text(_saving ? 'Đang lưu…' : 'Lưu quyết định')),
                        ),
                        if (attempts.length > 1) ...[
                          const SizedBox(height: 20),
                          const Text('Các lượt trong phiên',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
                          const SizedBox(height: 8),
                          NeoCard(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            child: Column(children: [
                              for (final (i, a) in attempts.indexed) _attemptRow(attempts.length - i, a, i == attempts.length - 1),
                            ]),
                          ),
                        ],
                      ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _decisionButton((String, String, IconData?) x) {
    final (value, label, icon) = x;
    final on = _choice == value;
    final reject = value == 'rejected';
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: on
            ? (reject ? const Color(0xFFFFE4E6) : value == 'manual_present' ? AppColors.presentSoft : AppColors.primarySoft)
            : (reject ? AppColors.absentSoft : Colors.white),
        foregroundColor: reject ? AppColors.absentText : on && value == 'manual_present' ? const Color(0xFF065F46) : AppColors.textLabel,
        side: BorderSide(
            color: on
                ? (reject ? AppColors.absentText : value == 'manual_present' ? AppColors.present : AppColors.primary)
                : (reject ? AppColors.absentBorder : AppColors.inputBorder),
            width: on ? 2 : 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: on ? FontWeight.w800 : FontWeight.w600),
      ),
      onPressed: () => setState(() => _choice = value),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (icon != null && on) ...[Icon(icon, size: 17), const SizedBox(width: 6)],
        Text(label),
      ]),
    );
  }

  Widget _attemptRow(int n, Map a, bool last) {
    final (label, fg) = switch (a['result']) {
      'pass' => ('Đạt', AppColors.presentText),
      'suspicious' => ('Đáng ngờ', const Color(0xFF92400E)),
      _ => ('Không đạt', AppColors.absentText),
    };
    final flags = (a['flags'] as List).cast<String>().map((f) => flagText(f, a).$1);
    final detail = a['result'] == 'fail' ? failText[a['fail_reason']] ?? '${a['fail_reason'] ?? ''}' : flags.join(', ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.cardBorder))),
      child: Row(children: [
        Text('#$n', style: mono.copyWith(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(width: 10),
        Text(hhmm(a['received_at']), style: mono.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        Expanded(child: Text(detail, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.attempt, this.image});
  final Map attempt;
  final Uint8List? image;

  @override
  Widget build(BuildContext context) {
    final a = attempt;
    final score = (a['face_score'] as num?)?.toDouble();
    final flags = (a['flags'] as List).cast<String>();
    final chips = <Widget>[
      if (score != null) _chip(Icons.face, 'Khuôn mặt ${score.toStringAsFixed(2).replaceAll('.', ',')}',
          ok: !flags.contains('FACE_BORDERLINE')),
      if (a['liveness_score'] != null && a['fail_reason'] != 'SPOOF_SUSPECTED') _chip(Icons.verified, 'Liveness đạt', ok: true),
      if (a['fail_reason'] == 'SPOOF_SUSPECTED') _chip(Icons.gpp_bad, 'Nghi giả mạo', ok: false),
      for (final f in flags.where((f) => f != 'FACE_BORDERLINE'))
        _chip(flagText(f, a).$2, f == 'LOCATION_DRIFT' ? 'Lệch vị trí nhẹ' : flagText(f, a).$1, ok: false),
    ];
    final summary = switch (a['result']) {
      'pass' => 'Lượt này đạt mọi kiểm tra.',
      'suspicious' => flags.length == 1 && flags.first == 'LOCATION_DRIFT'
          ? 'Chỉ vị trí rơi vào vùng lệch nhẹ. Các kiểm tra khác đều đạt.'
          : 'Có ${flags.length} dấu hiệu cần xem. Đối chiếu ảnh rồi quyết định.',
      _ => 'Lượt không đạt ở bước ${a['fail_step'] ?? '?'}.',
    };
    return HeroCard(
      emeraldGlow: false,
      padding: const EdgeInsets.all(12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 104, height: 130, color: const Color(0xFF111A2E),
            child: Stack(fit: StackFit.expand, children: [
              if (image != null)
                Image.memory(image!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())
              else
                const Icon(Icons.person, size: 72, color: Color(0xFF1E2A44)),
              if (a['has_evidence'] == true)
                Positioned(
                  left: 6, bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(6)),
                    child: Text('30 ngày', style: mono.copyWith(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final c in chips) ...[c, const SizedBox(height: 6)],
            Text(summary, style: const TextStyle(fontSize: 12, height: 17 / 12, color: AppColors.heroText)),
          ]),
        ),
      ]),
    );
  }

  static Widget _chip(IconData icon, String text, {required bool ok}) => Pill(text, icon: icon,
      bg: ok ? const Color(0x2610B981) : const Color(0x26F59E0B),
      fg: ok ? const Color(0xFF6EE7B7) : const Color(0xFFFCD34D),
      border: ok ? const Color(0x4D10B981) : const Color(0x4DF59E0B),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2));
}

class _DistanceCard extends StatelessWidget {
  const _DistanceCard(this.a);
  final Map a;

  @override
  Widget build(BuildContext context) {
    final d = (a['distance_m'] as num).toDouble();
    final r = (a['radius_m'] as num).toDouble();
    final pos = (d / (2 * r)).clamp(0.0, 1.0);
    final color = d <= r ? AppColors.presentText : d <= 2 * r ? const Color(0xFFB45309) : AppColors.absentText;
    return NeoCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Khoảng cách tới tâm phiên', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
          if (a['accuracy_m'] != null)
            Pill('GPS ±${(a['accuracy_m'] as num).round()} m', bg: const Color(0xFFF1F5F9), fg: AppColors.textSecondary,
                monospace: true, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1)),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 30,
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            return Stack(children: [
              Positioned(
                left: 0, right: 0, top: 11,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const SizedBox(height: 8, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: ColoredBox(color: Color(0xFFD1FAE5))),
                    Expanded(child: ColoredBox(color: Color(0xFFFEF3C7))),
                  ])),
                ),
              ),
              Positioned(left: w / 2 - 1, top: 7, child: Container(width: 2, height: 16, color: const Color(0xFF94A3B8))),
              Positioned(left: (w * pos - 2).clamp(0, w - 4), top: 2,
                  child: Container(width: 4, height: 26, decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(2)))),
            ]);
          }),
        ),
        const SizedBox(height: 4),
        DefaultTextStyle(
          style: mono.copyWith(fontSize: 11, color: AppColors.textMuted),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('0 m'),
            Text('r = ${r.round()} m'),
            Text('2r = ${(2 * r).round()} m'),
          ]),
        ),
        const SizedBox(height: 10),
        Text('d = ${d.round()} m', style: mono.copyWith(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }
}
