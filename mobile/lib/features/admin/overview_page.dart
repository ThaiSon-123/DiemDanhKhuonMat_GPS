import 'package:flutter/material.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import '../lecturer/live_session_page.dart' show failText, flagText;
import 'admin_widgets.dart';

/// Tổng quan cho quản trị theo học kỳ: GET /admin/overview. Tỉ lệ có mặt theo lớp, sinh viên vắng nhiều,
/// cờ đáng ngờ theo loại, lý do lượt không đạt.
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key, required this.session});
  final Session session;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  Map<String, dynamic>? _d;
  String? _semester;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await widget.session.api.get('/admin/overview', query: {'semester': ?_semester});
      if (mounted) {
        setState(() {
          _d = Map<String, dynamic>.from(r as Map);
          _semester = _d!['semester'] as String?;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return LoadingOrError(error: _error, onRetry: _load);
    final t = d['totals'] as Map;
    final classes = [for (final c in d['classes'] as List) Map<String, dynamic>.from(c as Map)];
    final semesters = (d['semesters'] as List).cast<String>();
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: webContentMaxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, alignment: WrapAlignment.spaceBetween,
                  children: [
                    AdminHeading('Tổng quan', subtitle: _semester == null ? 'Chưa có lớp nào' : 'Học kỳ $_semester'),
                    if (semesters.length > 1)
                      SizedBox(
                        width: 220,
                        child: AdminSelect<String>(
                          label: 'Học kỳ',
                          value: _semester,
                          options: {for (final s in semesters) s: s},
                          onChanged: (v) {
                            setState(() => _semester = v);
                            _load();
                          },
                        ),
                      ),
                  ]),
              if (_error != null) ...[const SizedBox(height: 12), ErrorNote(_error!)],
              const SizedBox(height: 20),
              _kpis(t, d['warn_absent'] as int),
              const SizedBox(height: 20),
              LayoutBuilder(builder: (context, c) {
                final wide = c.maxWidth >= 900;
                final classCard = _classCard(classes, d['warn_absent'] as int);
                final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _barsCard('Cờ đáng ngờ theo loại', 'Lượt có cờ thì vào danh sách chờ giảng viên duyệt',
                      [for (final f in d['flags'] as List) (f['flag'] == 'LOCATION_DRIFT' ? 'Lệch vị trí' : flagText('${f['flag']}', null).$1, f['n'] as int)],
                      const Color(0xFFF59E0B)),
                  const SizedBox(height: 20),
                  _barsCard('Lý do lượt không đạt', 'Gợi ý chỗ cần hướng dẫn sinh viên',
                      [for (final f in d['fail_reasons'] as List) (failText[f['reason']] ?? '${f['reason']}', f['n'] as int)],
                      AppColors.absent),
                ]);
                return wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 3, child: classCard),
                        const SizedBox(width: 20),
                        Expanded(flex: 2, child: side),
                      ])
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [classCard, const SizedBox(height: 20), side]);
              }),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _kpis(Map t, int warnAbsent) {
    final attempts = t['attempts'] as int;
    final firstPass = attempts == 0 ? null : (100 * (t['pass'] as int) / attempts).round();
    final items = [
      (Icons.check, 'Tỉ lệ có mặt', t['present_pct'] == null ? '–' : '${t['present_pct']}%', const Color(0x2610B981),
          const Color(0xFF34D399)),
      (Icons.event_available, 'Buổi đã điểm danh', '${t['sessions']}', const Color(0x336366F1), const Color(0xFFA5B4FC)),
      (Icons.warning_amber_rounded, 'SV vắng từ $warnAbsent buổi', '${t['warn_students']}', const Color(0x26F43F5E),
          const Color(0xFFFB7185)),
      (Icons.inbox_outlined, 'Đơn đang chờ', '${t['pending_requests']}', const Color(0x26F59E0B), const Color(0xFFFCD34D)),
      (Icons.bolt, 'Tỉ lệ lượt đạt', firstPass == null ? '–' : '$firstPass%', const Color(0x336366F1), const Color(0xFFA5B4FC)),
    ];
    return HeroCard(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / 200).floor().clamp(1, items.length);
        final w = (c.maxWidth - 12 * (cols - 1)) / cols;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final (icon, label, value, bg, fg) in items)
            Container(
              width: w,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x14FFFFFF))),
              child: Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, size: 21, color: fg)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                    Text(value, style: mono.copyWith(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                  ]),
                ),
              ]),
            ),
        ]);
      }),
    );
  }

  Widget _classCard(List<Map<String, dynamic>> classes, int warnAbsent) => NeoCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Tỉ lệ có mặt theo lớp', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 4),
          Text('Sắp xếp theo tỉ lệ thấp trước. Số đỏ: sinh viên vắng từ $warnAbsent buổi.',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 12),
          if (classes.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text('Chưa có lớp.', style: TextStyle(color: AppColors.textMuted))),
          for (final (i, c) in ([...classes]..sort((a, b) => ((a['present_pct'] ?? 101) as int).compareTo((b['present_pct'] ?? 101) as int))).indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.cardBorder))),
              child: Row(children: [
                SizedBox(width: 84, child: CodeChip('${c['code']}')),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c['name']}', overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
                    Text('${c['lecturer_name']} · ${c['students']} SV · ${c['sessions']} buổi', overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: c['present_pct'] == null
                      ? const Text('Chưa điểm danh', style: TextStyle(fontSize: 12, color: AppColors.textMuted))
                      : Row(children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: (c['present_pct'] as int) / 100,
                                minHeight: 8,
                                backgroundColor: AppColors.cardBorder,
                                color: (c['present_pct'] as int) >= 80 ? AppColors.present : const Color(0xFFF59E0B),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(width: 40, child: Text('${c['present_pct']}%', textAlign: TextAlign.right,
                              style: mono.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textLabel))),
                        ]),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 56,
                  child: (c['warn_students'] as int) > 0
                      ? Pill('${c['warn_students']}', icon: Icons.warning_amber_rounded, bg: AppColors.absentSoft,
                          fg: AppColors.absentText, border: AppColors.absentBorder)
                      : const SizedBox.shrink(),
                ),
              ]),
            ),
        ]),
      );

  Widget _barsCard(String title, String sub, List<(String, int)> items, Color color) {
    final max = items.fold<int>(0, (m, e) => e.$2 > m ? e.$2 : m);
    return NeoCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(height: 4),
        Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 12),
        if (items.isEmpty) const Text('Chưa có dữ liệu.', style: TextStyle(color: AppColors.textMuted)),
        for (final (label, n) in items) ...[
          Row(children: [
            Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppColors.textLabel))),
            Text('$n', style: mono.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: max == 0 ? 0 : n / max, minHeight: 6, backgroundColor: AppColors.cardBorder,
                color: color),
          ),
          const SizedBox(height: 10),
        ],
      ]),
    );
  }
}
