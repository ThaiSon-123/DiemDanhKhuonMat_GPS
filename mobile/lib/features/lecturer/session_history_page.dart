import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import 'live_session_page.dart' show hhmm;

/// Artboard "GV · Lịch sử phiên" (GV_LichSuPhien.dc.html). GET /classes/{id}/sessions; bấm một phiên để xem và sửa.
class SessionHistoryPage extends StatefulWidget {
  const SessionHistoryPage({super.key, required this.session, required this.classId, this.classCode = '',
      this.studentCount});
  final Session session;
  final int classId;
  final String classCode;
  final int? studentCount;

  @override
  State<SessionHistoryPage> createState() => _SessionHistoryPageState();
}

class _SessionHistoryPageState extends State<SessionHistoryPage> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await widget.session.api.get('/classes/${widget.classId}/sessions') as List;
      if (mounted) setState(() => _rows = [for (final x in r) Map<String, dynamic>.from(x as Map)]);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = [widget.classCode, if (widget.studentCount != null) '${widget.studentCount} sinh viên'].join(' · ');
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(children: [
              NeoHeader(label: label, title: 'Lịch sử phiên', onBack: () => context.go('/lecturer'), trailing: [
                HeaderTile(
                  tooltip: 'Báo cáo lớp',
                  onTap: () => context.push('/lecturer/report/${widget.classId}'),
                  child: const Icon(Icons.bar_chart, size: 20, color: AppColors.textSecondary),
                ),
              ]),
              Expanded(child: _rows == null ? LoadingOrError(error: _error, onRetry: _load) : _body(_rows!)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _body(List<Map<String, dynamic>> rows) {
    int c(Map r, String k) => (r['counts'] as Map)[k] as int;
    final rates = [for (final r in rows) if (c(r, 'total') > 0) c(r, 'present') / c(r, 'total')];
    final avg = rates.isEmpty ? null : (100 * rates.reduce((a, b) => a + b) / rates.length).round();
    final pending = rows.fold<int>(0, (s, r) => s + c(r, 'suspicious'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        HeroCard(
          glow: AppColors.glowEmerald,
          emeraldGlow: false,
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            _Kpi('Số buổi', '${rows.length}', Colors.white),
            const SizedBox(width: 8),
            _Kpi('Có mặt TB', avg == null ? '–' : '$avg%', const Color(0xFF34D399)),
            const SizedBox(width: 8),
            _Kpi('Chờ duyệt', '$pending', const Color(0xFFFBBF24)),
          ]),
        ),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            Icon(Icons.info_outline, size: 15, color: AppColors.textMuted),
            SizedBox(width: 6),
            Text('Sửa được sau khi đóng phiên · có ghi nhật ký', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const NeoCard(child: Text('Lớp chưa có phiên điểm danh nào.', style: TextStyle(color: AppColors.textMuted))),
        for (final r in rows) ...[_SessionRow(r, onTap: () => context.push('/lecturer/session/${r['id']}')), const SizedBox(height: 10)],
      ]),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x0FFFFFFF))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
            const SizedBox(height: 2),
            Text(value, style: mono.copyWith(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          ]),
        ),
      );
}

/// Ô ngày "10 / TH11".
class DateTile extends StatelessWidget {
  const DateTile(this.date, {super.key});
  final DateTime date;

  @override
  Widget build(BuildContext context) => Container(
        width: 46, height: 50,
        decoration: BoxDecoration(color: AppColors.inputFill, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(date.day.toString().padLeft(2, '0'),
              style: const TextStyle(fontSize: 17, height: 20 / 17, fontWeight: FontWeight.w800, color: AppColors.text)),
          Text('TH${date.month}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        ]),
      );
}

class _SessionRow extends StatelessWidget {
  const _SessionRow(this.r, {required this.onTap});
  final Map<String, dynamic> r;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = r['counts'] as Map;
    final total = c['total'] as int, present = c['present'] as int, sus = c['suspicious'] as int;
    final end = r['closed_at'] ?? r['expires_at'];
    return NeoCard(
      radius: 20,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            DateTile(DateTime.parse('${r['opened_at']}').toLocal()),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('$present/$total có mặt', style: mono.copyWith(fontSize: 13, fontWeight: FontWeight.w700))),
                  if (r['is_open'] == true)
                    const LivePill('Đang mở')
                  else
                    Text('${hhmm(r['opened_at'])}–${hhmm(end)}', style: mono.copyWith(fontSize: 11, color: AppColors.textMuted)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (present > 0) Expanded(flex: present, child: const ColoredBox(color: AppColors.present)),
                      if (sus > 0) ...[const SizedBox(width: 2), Expanded(flex: sus, child: const ColoredBox(color: Color(0xFFF59E0B)))],
                      if (total - present - sus > 0)
                        Expanded(flex: total - present - sus, child: const ColoredBox(color: Color(0xFFF1F5F9))),
                      if (total == 0) const Expanded(child: ColoredBox(color: Color(0xFFF1F5F9))),
                    ]),
                  ),
                ),
                if (sus > 0) ...[
                  const SizedBox(height: 6),
                  Pill('$sus lượt chờ duyệt', icon: Icons.hourglass_top, bg: const Color(0xFFFFFBEB), fg: const Color(0xFF92400E),
                      border: const Color(0xFFFDE68A), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1)),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
