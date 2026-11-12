import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import 'lecturer_nav.dart';
import 'live_session_page.dart' show avatarColors, statusStyle;
import 'open_session_page.dart' show Segmented;

/// Đơn xin nghỉ và khiếu nại của sinh viên các lớp mình dạy. GET /requests, POST /requests/{id}/decide,
/// GET /requests/{id}/attachment. Duyệt: xin nghỉ → vắng có phép, khiếu nại → có mặt (khóa như duyệt tay).
class LecturerRequestsPage extends StatefulWidget {
  const LecturerRequestsPage({super.key, required this.session});
  final Session session;

  @override
  State<LecturerRequestsPage> createState() => _LecturerRequestsPageState();
}

class _LecturerRequestsPageState extends State<LecturerRequestsPage> {
  List<Map<String, dynamic>>? _rows;
  String? _error;
  int _tab = 0; // 0 chờ duyệt, 1 đã xử lý
  final _busy = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await widget.session.api.get('/requests', query: {'status': 'all'}) as List;
      if (mounted) setState(() => _rows = [for (final x in r) Map<String, dynamic>.from(x as Map)]);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _decide(Map<String, dynamic> r, bool approve) async {
    final note = await _askNote(approve, r);
    if (note == null) return;
    setState(() => _busy.add(r['id'] as int));
    try {
      await widget.session.api.post('/requests/${r['id']}/decide',
          data: {'decision': approve ? 'approve' : 'reject', 'note': note.isEmpty ? null : note});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(approve ? 'Đã duyệt đơn của ${r['full_name']}' : 'Đã từ chối đơn của ${r['full_name']}'),
            behavior: SnackBarBehavior.floating));
      }
      await _load();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy.remove(r['id']));
    }
  }

  /// Hỏi ghi chú: duyệt thì không bắt buộc, từ chối thì bắt buộc. null = hủy.
  Future<String?> _askNote(bool approve, Map<String, dynamic> r) {
    final c = TextEditingController();
    final leave = r['kind'] == 'leave';
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(approve ? 'Duyệt đơn của ${r['full_name']}?' : 'Từ chối đơn của ${r['full_name']}?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(approve
                ? 'Buổi này sẽ được ghi "${leave ? 'Vắng có phép' : 'Có mặt (duyệt tay)'}" và không bị hệ thống ghi đè.'
                : 'Sinh viên sẽ thấy lý do từ chối và có thể gửi lại đơn khác.'),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              maxLines: 2,
              maxLength: 500,
              autofocus: !approve,
              onChanged: (_) => set(() {}),
              decoration: InputDecoration(labelText: approve ? 'Ghi chú (không bắt buộc)' : 'Lý do từ chối', counterText: ''),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              style: (approve ? FilledButton.styleFrom() : FilledButton.styleFrom(backgroundColor: AppColors.absentText))
                  .merge(dialogButtonStyle),
              onPressed: !approve && c.text.trim().isEmpty ? null : () => Navigator.pop(ctx, c.text.trim()),
              child: Text(approve ? 'Duyệt' : 'Từ chối'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAttachment(Map<String, dynamic> r) async {
    try {
      final Uint8List b = await widget.session.api.getBytes('/requests/${r['id']}/attachment');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: InteractiveViewer(child: Image.memory(b, fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Padding(padding: EdgeInsets.all(24), child: Text('Không mở được ảnh'))))),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          ]),
        ),
      );
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final pending = rows?.where((r) => r['status'] == 'pending').toList();
    return PhoneShell(
      header: const NeoHeader(label: 'Giảng viên', title: 'Đơn của sinh viên'),
      dock: lecturerDock(context, widget.session, 2, requests: pending?.length),
      body: rows == null
          ? LoadingOrError(error: _error, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
                Segmented(
                  dark: true,
                  background: Colors.white,
                  options: ['Chờ duyệt · ${pending!.length}', 'Đã xử lý'],
                  selected: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
                if (_error != null) ...[const SizedBox(height: 12), ErrorNote(_error!)],
                const SizedBox(height: 12),
                if ((_tab == 0 ? pending : rows.where((r) => r['status'] != 'pending')).isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(_tab == 0 ? 'Không có đơn nào đang chờ.' : 'Chưa xử lý đơn nào.',
                        textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
                  ),
                for (final (i, r) in (_tab == 0 ? pending : rows.where((r) => r['status'] != 'pending')).indexed) ...[
                  _card(i, r),
                  const SizedBox(height: 10),
                ],
              ]),
            ),
    );
  }

  Widget _card(int i, Map<String, dynamic> r) {
    final (bg, fg) = avatarColors[i % avatarColors.length];
    final leave = r['kind'] == 'leave';
    final d = DateTime.parse('${r['opened_at']}').toLocal();
    final rec = statusStyle['${r['record_status']}'];
    final busy = _busy.contains(r['id']);
    return NeoCard(
      radius: 20,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          InitialsAvatar('${r['full_name']}', bg: bg, fg: fg, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['full_name']}', overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
              Text('${r['student_code']} · ${r['class_code']} · buổi ${d.day.toString().padLeft(2, '0')}/'
                  '${d.month.toString().padLeft(2, '0')}', style: mono.copyWith(fontSize: 11, color: AppColors.textMuted)),
            ]),
          ),
          Pill(leave ? 'Xin nghỉ' : 'Khiếu nại', icon: leave ? Icons.description : Icons.report_outlined,
              bg: leave ? AppColors.primarySoft : const Color(0xFFFFFBEB), fg: leave ? const Color(0xFF4338CA) : const Color(0xFF92400E),
              border: leave ? const Color(0xFFE0E7FF) : const Color(0xFFFDE68A)),
        ]),
        const SizedBox(height: 10),
        Text('${r['reason']}', style: const TextStyle(fontSize: 14, height: 20 / 14, color: AppColors.textLabel)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (rec != null)
            Pill('Hiện ghi: ${rec.$1}', bg: rec.$3, fg: rec.$4, border: rec.$5, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
          if (r['has_attachment'] == true)
            ActionChip(
              avatar: const Icon(Icons.image_outlined, size: 16),
              label: const Text('Xem giấy tờ'),
              onPressed: () => _showAttachment(r),
            ),
        ]),
        if (r['status'] == 'pending') ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.absentText, backgroundColor: AppColors.absentSoft,
                      side: const BorderSide(color: AppColors.absentBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: busy ? null : () => _decide(r, false),
                  child: const Text('Từ chối', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 44,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44), elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: busy ? null : () => _decide(r, true),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Duyệt'),
                ),
              ),
            ),
          ]),
        ] else ...[
          const SizedBox(height: 10),
          Text(
            '${r['status'] == 'approved' ? 'Đã duyệt' : 'Đã từ chối'}'
            '${r['decision_note'] == null ? '' : ': ${r['decision_note']}'}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: r['status'] == 'approved' ? AppColors.presentText : AppColors.absentText),
          ),
        ],
      ]),
    );
  }
}
