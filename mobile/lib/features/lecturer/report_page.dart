import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/files.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import 'live_session_page.dart' show avatarColors;

/// Artboard "Web · Báo cáo" (Web_BaoCao.dc.html). GET /reports/classes/{id}, `?format=csv` để xuất.
/// Dùng trong trang quản trị (chọn mọi lớp) và cho giảng viên (lớp mình; [standalone] có đầu trang riêng).
class ReportPage extends StatefulWidget {
  const ReportPage({super.key, required this.session, this.classId, this.standalone = false});
  final Session session;
  final int? classId;
  final bool standalone;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  List<Map<String, dynamic>>? _classes;
  int? _classId;
  Map<String, dynamic>? _report;
  DateTime? _loadedAt;
  String? _error;

  bool get _admin => widget.session.role == 'admin';

  @override
  void initState() {
    super.initState();
    _classId = widget.classId;
    _init();
  }

  Future<void> _init() async {
    setState(() => _error = null);
    try {
      final r = _admin
          ? await widget.session.api.get('/admin/classes', query: {'size': 200})
          : await widget.session.api.get('/me/classes');
      final list = [for (final c in (r is Map ? r['items'] : r) as List) Map<String, dynamic>.from(c as Map)];
      if (!mounted) return;
      setState(() {
        _classes = list;
        _classId ??= list.firstOrNull?['id'] as int?;
      });
      await _load();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _load() async {
    if (_classId == null) return;
    setState(() {
      _report = null;
      _error = null;
    });
    try {
      final r = await widget.session.api.get('/reports/classes/$_classId') as Map;
      if (mounted) {
        setState(() {
          _report = Map<String, dynamic>.from(r);
          _loadedAt = DateTime.now();
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String? _exporting;

  /// Xuất báo cáo: xlsx (tổng hợp + chi tiết từng buổi), pdf (A4, có chỗ ký), csv (dữ liệu thô).
  Future<void> _export(String fmt) async {
    setState(() {
      _exporting = fmt;
      _error = null;
    });
    final c = _report?['class'] as Map?;
    final name = 'bao-cao-chuyen-can-${c?['code'] ?? _classId}-${c?['semester'] ?? ''}.$fmt';
    try {
      if (fmt == 'csv') {
        final csv = await widget.session.api.get('/reports/classes/$_classId', query: {'format': 'csv'});
        downloadText(name, '$csv'.replaceFirst('\uFEFF', ''));
      } else {
        final b = await widget.session.api.getBytes('/reports/classes/$_classId', query: {'format': fmt});
        downloadBytes(name, b, fmt == 'pdf' ? 'application/pdf' : _xlsxMime);
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on UnsupportedError {
      if (mounted) setState(() => _error = 'Xuất file dùng trên bản web (laptop).');
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  static const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  @override
  Widget build(BuildContext context) {
    final body = _classes == null
        ? LoadingOrError(error: _error, onRetry: _init)
        : _classes!.isEmpty
            ? const Center(child: Text('Chưa có lớp nào.', style: TextStyle(color: AppColors.textMuted)))
            : _content();
    if (!widget.standalone) return body;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          NeoHeader(
            label: 'Giảng dạy',
            title: 'Báo cáo chuyên cần',
            onBack: () => context.canPop() ? context.pop() : context.go('/lecturer'),
          ),
          Expanded(child: body),
        ]),
      ),
    );
  }

  Widget _content() {
    final r = _report;
    return LayoutBuilder(builder: (context, c) {
      final pad = c.maxWidth >= 700 ? 32.0 : 16.0;
      return ListView(padding: EdgeInsets.fromLTRB(pad, 20, pad, 40), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: webContentMaxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 340,
                  child: DropdownButtonFormField<int>(
                    initialValue: _classId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Chọn lớp', isDense: true),
                    items: [
                      for (final k in _classes!)
                        DropdownMenuItem(value: k['id'] as int, child: Text('${k['code']} · ${k['name']} · ${k['semester']}',
                            overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      setState(() => _classId = v);
                      _load();
                    },
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: r == null || _exporting != null ? null : () => _export('xlsx'),
                    icon: const Icon(Icons.table_view, size: 18),
                    label: Text(_exporting == 'xlsx' ? 'Đang xuất…' : 'Xuất Excel'),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.text,
                        side: const BorderSide(color: AppColors.inputBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: r == null || _exporting != null ? null : () => _export('pdf'),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18, color: AppColors.absentText),
                    label: Text(_exporting == 'pdf' ? 'Đang xuất…' : 'PDF nộp khoa'),
                  ),
                ),
                TextButton(
                  onPressed: r == null || _exporting != null ? null : () => _export('csv'),
                  child: const Text('CSV'),
                ),
              ]),
              const SizedBox(height: 20),
              if (_error != null) ...[ErrorNote(_error!), const SizedBox(height: 16)],
              if (r == null && _error == null)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (r != null)
                ..._reportBody(r),
            ]),
          ),
        ),
      ]);
    });
  }

  List<Widget> _reportBody(Map<String, dynamic> r) {
    final rows = [for (final x in r['rows'] as List) Map<String, dynamic>.from(x as Map)];
    final sessions = [for (final x in r['sessions'] as List) Map<String, dynamic>.from(x as Map)];
    int n(Map m, String k) => (m[k] as num).toInt();
    final rates = [for (final s in sessions) if (n(s, 'total') > 0) n(s, 'present') / n(s, 'total')];
    final avg = rates.isEmpty ? null : (100 * rates.reduce((a, b) => a + b) / rates.length).round();
    final many = rows.where((x) => x['warn'] == true).length;
    final pending = rows.fold<int>(0, (s, x) => s + n(x, 'chua_duyet'));
    final at = _loadedAt!;
    String two(int v) => v.toString().padLeft(2, '0');
    return [
      Text('Báo cáo chuyên cần · ${r['class']['name']}',
          style: const TextStyle(fontSize: 28, height: 36 / 28, fontWeight: FontWeight.w800, color: AppColors.text)),
      const SizedBox(height: 6),
      Text('${rows.length} sinh viên · ${r['session_count']} buổi đã điểm danh · cập nhật '
          '${two(at.hour)}:${two(at.minute)}, ${two(at.day)}/${two(at.month)}/${at.year}',
          style: const TextStyle(fontSize: 15, color: AppColors.textMuted)),
      const SizedBox(height: 20),
      HeroCard(
        emeraldGlow: true,
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(builder: (context, c) {
          final cols = (c.maxWidth / 222).floor().clamp(1, 4);
          final w = (c.maxWidth - 12 * (cols - 1)) / cols;
          final kpis = [
            (Icons.check, 'Tỉ lệ có mặt trung bình', avg == null ? '–' : '$avg%', const Color(0x2610B981), const Color(0xFF34D399)),
            (Icons.error_outline, 'Vắng từ ${r['warn_absent'] ?? 3} buổi trở lên', '$many SV', const Color(0x26F43F5E), const Color(0xFFFB7185)),
            (Icons.schedule, 'Lượt chờ duyệt', '$pending', const Color(0x26F59E0B), const Color(0xFFFCD34D)),
            (Icons.bolt, 'Thành công ngay lần đầu', r['first_try_pct'] == null ? '–' : '${r['first_try_pct']}%',
                const Color(0x336366F1), const Color(0xFFA5B4FC)),
          ];
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final (icon, label, value, bg, fg) in kpis)
              Container(
                width: w,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0x14FFFFFF))),
                child: Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                      child: Icon(icon, size: 22, color: fg)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                      Text(value, style: mono.copyWith(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
                    ]),
                  ),
                ]),
              ),
          ]);
        }),
      ),
      const SizedBox(height: 20),
      NeoCard(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 8, children: [
            Text('Tỉ lệ có mặt theo buổi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _Legend(AppColors.primary, 'Có mặt'),
              SizedBox(width: 14),
              _Legend(Color(0xFFF2A33A), 'Chờ duyệt'),
            ]),
          ]),
          const SizedBox(height: 16),
          if (sessions.isEmpty)
            const Text('Chưa có buổi nào.', style: TextStyle(color: AppColors.textMuted))
          else
            SizedBox(
              height: 180,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final s in sessions.length > 12 ? sessions.sublist(sessions.length - 12) : sessions)
                  Expanded(child: _Bar(s)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 20),
      NeoCard(
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: c.maxWidth < 720 ? 720 : c.maxWidth,
              child: Column(children: [
                _tableRow(const ['Sinh viên', 'Có mặt', 'Có phép', 'Vắng', 'Chờ duyệt', 'Tỉ lệ có mặt'], header: true),
                for (final (i, x) in rows.indexed) _studentRow(i, x),
              ]),
            ),
          ),
        ),
      ),
    ];
  }

  static const _flex = [32, 11, 11, 11, 11, 24];

  Widget _tableRow(List<Object> cells, {bool header = false, Color? absentColor}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: header ? AppColors.inputFill : null,
          border: header ? null : const Border(top: BorderSide(color: AppColors.cardBorder)),
        ),
        child: Row(children: [
          for (final (i, c) in cells.indexed)
            Expanded(
              flex: _flex[i],
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: header ? 10 : 12),
                child: c is Widget
                    ? c
                    : Text('$c', textAlign: i > 0 && i < 5 ? TextAlign.right : TextAlign.left,
                        style: header
                            ? const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)
                            : TextStyle(fontSize: 14, color: i == 3 && absentColor != null ? absentColor : AppColors.text,
                                fontWeight: i == 3 && absentColor != null ? FontWeight.w700 : FontWeight.w400,
                                fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ),
        ]),
      );

  Widget _studentRow(int i, Map<String, dynamic> x) {
    final total = (x['so_buoi'] as num).toInt();
    final present = (x['co_mat'] as num).toInt();
    final pct = total == 0 ? 0 : (100 * present / total).round();
    final bad = x['warn'] == true;
    final (bg, fg) = avatarColors[i % avatarColors.length];
    return _tableRow([
      Row(children: [
        InitialsAvatar('${x['full_name']}', bg: bg, fg: fg, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${x['full_name']}', overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
            Text('${x['student_code']}', style: mono.copyWith(fontSize: 11, color: AppColors.textMuted)),
          ]),
        ),
      ]),
      x['co_mat'], x['vang_co_phep'], x['vang'], x['chua_duyet'],
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: pct / 100, minHeight: 8, backgroundColor: AppColors.cardBorder,
                color: bad ? AppColors.absent : pct >= 80 ? AppColors.present : const Color(0xFFF59E0B)),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(width: 40, child: Text('$pct%', textAlign: TextAlign.right,
            style: mono.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textLabel))),
      ]),
    ], absentColor: bad ? AppColors.absentText : null);
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ]);
}

class _Bar extends StatelessWidget {
  const _Bar(this.s);
  final Map<String, dynamic> s;

  @override
  Widget build(BuildContext context) {
    final total = (s['total'] as num).toInt();
    final present = (s['present'] as num).toInt();
    final sus = (s['suspicious'] as num).toInt();
    final pct = total == 0 ? 0.0 : present / total;
    final pend = total == 0 ? 0.0 : sus / total;
    final d = DateTime.parse('${s['opened_at']}').toLocal();
    const maxH = 120.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text('${(pct * 100).round()}%', style: mono.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textLabel)),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxWidth: 44),
          height: (maxH * (pct + pend)).clamp(6, maxH),
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(borderRadius: BorderRadius.vertical(top: Radius.circular(8), bottom: Radius.circular(4))),
          child: Column(children: [
            if (pend > 0) Expanded(flex: sus, child: const ColoredBox(color: Color(0xFFF2A33A), child: SizedBox.expand())),
            Expanded(flex: present == 0 ? 1 : present, child: const ColoredBox(color: AppColors.primary, child: SizedBox.expand())),
          ]),
        ),
        const SizedBox(height: 6),
        Text('${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ]),
    );
  }
}
