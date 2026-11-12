import 'package:flutter/material.dart';

import '../../core/api_error.dart';
import '../../core/files.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import 'admin_widgets.dart';

/// Danh sách sinh viên không đủ điều kiện dự thi theo học kỳ: GET /admin/banned (JSON, xlsx, pdf).
/// Tiêu chí: vắng không phép quá `grading.ban_absent_pct` % số buổi của lớp.
class BannedPage extends StatefulWidget {
  const BannedPage({super.key, required this.session});
  final Session session;

  @override
  State<BannedPage> createState() => _BannedPageState();
}

class _BannedPageState extends State<BannedPage> {
  Map<String, dynamic>? _d;
  String? _semester;
  String? _error;
  String? _exporting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await widget.session.api.get('/admin/banned', query: {'semester': ?_semester});
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

  Future<void> _export(String fmt) async {
    setState(() => _exporting = fmt);
    try {
      final b = await widget.session.api.getBytes('/admin/banned', query: {'format': fmt, 'semester': ?_semester});
      downloadBytes('danh-sach-cam-thi-$_semester.$fmt', b,
          fmt == 'pdf' ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on UnsupportedError {
      if (mounted) setState(() => _error = 'Xuất file dùng trên bản web (laptop).');
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return LoadingOrError(error: _error, onRetry: _load);
    final rows = [for (final r in d['rows'] as List) Map<String, dynamic>.from(r as Map)];
    final semesters = (d['semesters'] as List? ?? const []).cast<String>();
    final byClass = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      byClass.putIfAbsent('${r['class_code']} · ${r['class_name']}', () => []).add(r);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: webContentMaxWidth),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AdminHeading('Không đủ điều kiện dự thi',
                subtitle: 'Học kỳ ${_semester ?? '–'} · vắng không phép quá ${d['ban_absent_pct']}% số buổi của lớp'),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (semesters.length > 1)
                SizedBox(
                  width: 200,
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
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: _exporting != null ? null : () => _export('pdf'),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: Text(_exporting == 'pdf' ? 'Đang xuất…' : 'PDF nộp phòng đào tạo'),
                ),
              ),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  style: adminOutlinedStyle(),
                  onPressed: _exporting != null ? null : () => _export('xlsx'),
                  icon: const Icon(Icons.table_view, size: 18),
                  label: Text(_exporting == 'xlsx' ? 'Đang xuất…' : 'Excel'),
                ),
              ),
            ]),
            if (_error != null) ...[const SizedBox(height: 12), ErrorNote(_error!)],
            const SizedBox(height: 20),
            if (rows.isEmpty)
              const NeoCard(
                child: Row(children: [
                  Icon(Icons.verified, color: AppColors.present),
                  SizedBox(width: 10),
                  Text('Không có sinh viên nào bị cấm thi trong học kỳ này.', style: TextStyle(color: AppColors.textSecondary)),
                ]),
              ),
            for (final e in byClass.entries) ...[
              NeoCard(
                padding: EdgeInsets.zero,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                    child: Row(children: [
                      Expanded(child: Text(e.key, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
                      Pill('${e.value.length} SV', bg: AppColors.absentSoft, fg: AppColors.absentText, border: AppColors.absentBorder),
                    ]),
                  ),
                  for (final r in e.value)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.cardBorder))),
                      child: Row(children: [
                        SizedBox(width: 90, child: Text('${r['student_code']}', style: mono.copyWith(fontSize: 13))),
                        Expanded(child: Text('${r['full_name']}', style: const TextStyle(fontSize: 14, color: AppColors.text))),
                        Text('Vắng ${r['vang']}/${r['so_buoi']} buổi', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        const SizedBox(width: 12),
                        SizedBox(width: 48, child: Text('${r['pct']}%', textAlign: TextAlign.right,
                            style: mono.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.absentText))),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 14),
            ],
          ]),
        ),
      ),
    );
  }
}
