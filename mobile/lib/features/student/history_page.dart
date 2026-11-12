import 'package:flutter/material.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import '../lecturer/live_session_page.dart' show hhmm;
import '../lecturer/session_history_page.dart' show DateTile;
import 'request_sheet.dart';
import 'student_nav.dart';

/// Trạng thái hiển thị cho sinh viên (không bao giờ thấy điểm số): nhãn, biểu tượng, nền, chữ, viền.
const _status = <String, (String, IconData, Color, Color, Color)>{
  'present': ('Có mặt', Icons.check_circle, AppColors.presentSoft, AppColors.presentText, AppColors.presentBorder),
  'excused': ('Có phép', Icons.description, Color(0xFFF1F5F9), AppColors.textLabel, AppColors.inputBorder),
  'absent': ('Vắng', Icons.cancel, AppColors.absentSoft, AppColors.absentText, AppColors.absentBorder),
  'pending': ('Chờ duyệt', Icons.hourglass_top, Color(0xFFFFFBEB), Color(0xFF92400E), Color(0xFFFDE68A)),
};

String _kind(String s) => switch (s) {
      'present' || 'manual_present' => 'present',
      'excused' => 'excused',
      'suspicious' => 'pending',
      _ => 'absent',
    };

/// Artboard "SV · Lịch sử chuyên cần" (SV_LichSu.dc.html). GET /me/attendance, nhóm theo lớp.
class StudentHistoryPage extends StatefulWidget {
  const StudentHistoryPage({super.key, required this.session});
  final Session session;

  @override
  State<StudentHistoryPage> createState() => _StudentHistoryPageState();
}

class _StudentHistoryPageState extends State<StudentHistoryPage> {
  List<Map<String, dynamic>>? _rows;
  Map<int, Map<String, dynamic>> _requests = {}; // đơn mới nhất của mỗi buổi
  Map<String, Map<String, dynamic>> _classes = {}; // theo mã lớp: số buổi vắng, cảnh báo
  String? _error;
  String? _code;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final api = widget.session.api;
      final res = await Future.wait([api.get('/me/attendance'), api.get('/me/requests'), api.get('/me/classes')]);
      if (!mounted) return;
      setState(() {
        _rows = [for (final x in res[0] as List) Map<String, dynamic>.from(x as Map)];
        _requests = {};
        for (final x in res[1] as List) {
          _requests.putIfAbsent((x as Map)['session_id'] as int, () => Map<String, dynamic>.from(x)); // id giảm dần
        }
        _classes = {for (final c in res[2] as List) '${(c as Map)['code']}': Map<String, dynamic>.from(c)};
        _code ??= _rows!.firstOrNull?['class_code'] as String?;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => PhoneShell(
        header: const NeoHeader(label: 'Điểm danh', title: 'Lịch sử chuyên cần'),
        dock: studentDock(context, 1),
        body: _rows == null ? LoadingOrError(error: _error, onRetry: _load) : _body(_rows!),
      );

  Widget _body(List<Map<String, dynamic>> all) {
    final codes = <String>{for (final r in all) '${r['class_code']}'}.toList();
    final rows = all.where((r) => r['class_code'] == _code).toList(); // mới nhất trước
    final count = {for (final k in _status.keys) k: rows.where((r) => _kind('${r['status']}') == k).length};
    final total = rows.length;
    final pct = total == 0 ? 0 : (100 * count['present']! / total).round();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
        if (all.isEmpty)
          const NeoCard(child: Text('Chưa có buổi điểm danh nào.', style: TextStyle(color: AppColors.textMuted)))
        else ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final c in codes) ...[
                ChoiceChip(
                  label: Text(c, style: mono.copyWith(fontSize: 12, fontWeight: c == _code ? FontWeight.w700 : FontWeight.w600,
                      color: c == _code ? Colors.white : AppColors.textLabel)),
                  selected: c == _code,
                  showCheckmark: false,
                  selectedColor: AppColors.text,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: c == _code ? AppColors.text : AppColors.inputBorder),
                  shape: const StadiumBorder(),
                  onSelected: (_) => setState(() => _code = c),
                ),
                const SizedBox(width: 6),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          HeroCard(
            glow: AppColors.glowEmerald,
            emeraldGlow: false,
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${rows.firstOrNull?['class_name'] ?? ''} · tỉ lệ có mặt',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                    const SizedBox(height: 2),
                    Text('$pct%', style: const TextStyle(fontSize: 38, height: 44 / 38, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                  ]),
                ),
                Pill('${count['present']}/$total buổi', bg: const Color(0x14FFFFFF), fg: AppColors.heroText,
                    border: const Color(0x1FFFFFFF), monospace: true, fontSize: 12),
              ]),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final (k, color) in const [
                      ('present', Color(0xFF34D399)),
                      ('pending', Color(0xFFFBBF24)),
                      ('excused', Color(0xFF94A3B8)),
                      ('absent', Color(0xFFFB7185)),
                    ])
                      if (count[k]! > 0) Expanded(flex: count[k]!, child: Padding(
                          padding: const EdgeInsets.only(right: 3), child: ColoredBox(color: color))),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 14, runSpacing: 6, children: [
                _legend(const Color(0xFF34D399), 'Có mặt ${count['present']}'),
                if (count['pending']! > 0) _legend(const Color(0xFFFBBF24), 'Chờ duyệt ${count['pending']}'),
                _legend(const Color(0xFF94A3B8), 'Có phép ${count['excused']}'),
                _legend(const Color(0xFFFB7185), 'Vắng ${count['absent']}'),
              ]),
            ]),
          ),
          if (_classes[_code]?['warn'] == true) ...[
            const SizedBox(height: 12),
            absenceWarning(_classes[_code]!['absences'] as int, _classes[_code]!['warn_absent'] as int),
          ],
          const SizedBox(height: 12),
          for (final (i, r) in rows.indexed) ...[_row(total - i, r), const SizedBox(height: 10)],
        ],
      ]),
    );
  }

  static Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(t, style: const TextStyle(fontSize: 12, color: AppColors.heroText)),
      ]);

  Widget _row(int n, Map<String, dynamic> r) {
    final k = _kind('${r['status']}');
    final (label, icon, bg, fg, border) = _status[k]!;
    final sub = r['checked_at'] != null
        ? 'Điểm danh lúc ${hhmm(r['checked_at'])}'
        : r['status'] == 'excused'
            ? 'Có đơn xin nghỉ'
            : r['status'] == 'manual_present'
                ? 'Giảng viên điểm danh tay'
                : 'Không điểm danh';
    final req = _requests[r['session_id']];
    final can = canRequest(r, req);
    return NeoCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          DateTile(DateTime.parse('${r['opened_at']}').toLocal()),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Buổi $n', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ),
          Pill(label, icon: icon, bg: bg, fg: fg, border: border, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3)),
        ]),
        if (req != null) ...[const SizedBox(height: 10), requestLine(req)],
        if (can) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                if (await showRequestSheet(context, widget.session, r) == true) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Đã gửi đơn. Giảng viên sẽ xem và trả lời.'), behavior: SnackBarBehavior.floating));
                  }
                  _load();
                }
              },
              icon: const Icon(Icons.edit_note, size: 18),
              label: Text(req == null ? 'Xin nghỉ / khiếu nại' : 'Gửi đơn khác'),
            ),
          ),
        ],
      ]),
    );
  }
}
