import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import '../lecturer/open_session_page.dart' show Segmented;

/// Hạn gửi đơn sau buổi học; server kiểm tra lại theo `attendance.request_days`.
const requestDays = 14;

/// Buổi này còn gửi đơn được không: đã đóng, đang ghi vắng / bị từ chối, trong hạn, chưa có đơn đang chờ.
bool canRequest(Map<String, dynamic> row, Map<String, dynamic>? latest, {DateTime? now}) {
  if (row['is_open'] == true || !const {'absent', 'rejected'}.contains(row['status'])) return false;
  if (latest?['status'] == 'pending') return false;
  final opened = DateTime.parse('${row['opened_at']}').toLocal();
  return (now ?? DateTime.now()).difference(opened) <= const Duration(days: requestDays);
}

/// Chọn ảnh giấy tờ: điện thoại chụp hoặc chọn từ thư viện, web chọn file. Tách ra để test thay được.
typedef PickImage = Future<(Uint8List, String)?> Function(ImageSource source);

Future<(Uint8List, String)?> _pick(ImageSource source) async {
  final f = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
  if (f == null) return null;
  return (await f.readAsBytes(), f.name);
}

/// Bảng gửi đơn xin nghỉ hoặc khiếu nại cho một buổi. Trả true khi đã gửi.
Future<bool?> showRequestSheet(BuildContext context, Session session, Map<String, dynamic> row, {PickImage? pick}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _RequestSheet(session: session, row: row, pick: pick ?? _pick),
    );

class _RequestSheet extends StatefulWidget {
  const _RequestSheet({required this.session, required this.row, required this.pick});
  final Session session;
  final Map<String, dynamic> row;
  final PickImage pick;

  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  // Bị giảng viên từ chối lượt thì mặc định là khiếu nại, vắng thì là xin nghỉ.
  late String _kind = widget.row['status'] == 'rejected' ? 'appeal' : 'leave';
  final _reason = TextEditingController();
  (Uint8List, String)? _file;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _attach(ImageSource source) async {
    try {
      final f = await widget.pick(source);
      if (f != null && mounted) setState(() => _file = f);
    } catch (e) {
      if (mounted) setState(() => _error = 'Không chọn được ảnh: $e');
    }
  }

  Future<void> _send() async {
    final reason = _reason.text.trim();
    if (reason.length < 5) {
      setState(() => _error = 'Hãy ghi lý do (ít nhất 5 ký tự)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final f = _file;
      final png = f != null && f.$2.toLowerCase().endsWith('.png');
      await widget.session.api.post('/me/requests', data: FormData.fromMap({
        'kind': _kind,
        'session_id': widget.row['session_id'],
        'reason': reason,
        if (f != null)
          'attachment': MultipartFile.fromBytes(f.$1, filename: f.$2, contentType: DioMediaType('image', png ? 'png' : 'jpeg')),
      }));
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.parse('${widget.row['opened_at']}').toLocal();
    final leave = _kind == 'leave';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('${widget.row['class_code']} · buổi ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}',
                style: mono.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
            const SizedBox(height: 2),
            const Text('Gửi đơn cho giảng viên', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 14),
            Segmented(
              options: const ['Xin nghỉ có phép', 'Khiếu nại kết quả'],
              selected: leave ? 0 : 1,
              onChanged: (i) => setState(() => _kind = i == 0 ? 'leave' : 'appeal'),
            ),
            const SizedBox(height: 8),
            Text(
              leave
                  ? 'Đã nghỉ vì lý do chính đáng (ốm, việc gia đình…). Được duyệt thì buổi này ghi "Vắng có phép".'
                  : 'Bạn có mặt nhưng hệ thống ghi vắng (GPS, camera lỗi…). Được duyệt thì buổi này ghi "Có mặt".',
              style: const TextStyle(fontSize: 12, height: 17 / 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            NeoCard(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _reason,
                  maxLines: 3,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    labelText: 'Lý do',
                    hintText: leave ? 'Vd: em bị sốt, có giấy khám của trạm y tế' : 'Vd: em ngồi bàn cuối, GPS báo lệch',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  if (_file != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_file!.$1, width: 56, height: 56, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.square(dimension: 56, child: Icon(Icons.image))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_file!.$2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                    IconButton(tooltip: 'Bỏ ảnh', onPressed: () => setState(() => _file = null), icon: const Icon(Icons.close, size: 18)),
                  ] else ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _attach(ImageSource.gallery),
                        icon: const Icon(Icons.attach_file, size: 18),
                        label: Text(kIsWeb ? 'Đính kèm ảnh giấy tờ' : 'Chọn ảnh giấy tờ'),
                      ),
                    ),
                    if (!kIsWeb) ...[
                      const SizedBox(width: 8),
                      IconButton.outlined(tooltip: 'Chụp ảnh', onPressed: () => _attach(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined, size: 20)),
                    ],
                  ],
                ]),
                const SizedBox(height: 6),
                Text(leave ? 'Nên đính kèm giấy tờ (đơn có xác nhận, giấy khám…). JPEG hoặc PNG, tối đa 5 MB.'
                    : 'Có thể đính kèm ảnh chụp màn hình lỗi nếu có.',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ]),
            ),
            if (_error != null) ...[const SizedBox(height: 10), ErrorNote(_error!)],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _send,
              icon: const Icon(Icons.send, size: 18),
              label: Text(_busy ? 'Đang gửi…' : 'Gửi đơn'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Dòng trạng thái đơn mới nhất của một buổi (dưới mỗi buổi trong Lịch sử).
Widget requestLine(Map<String, dynamic> r) {
  final kind = r['kind'] == 'leave' ? 'Đơn xin nghỉ' : 'Khiếu nại';
  final (text, icon, bg, fg, border) = switch (r['status']) {
    'pending' => ('$kind: chờ giảng viên duyệt', Icons.hourglass_top, const Color(0xFFFFFBEB), const Color(0xFF92400E),
        const Color(0xFFFDE68A)),
    'approved' => ('$kind: đã được duyệt', Icons.check_circle, AppColors.presentSoft, AppColors.presentText, AppColors.presentBorder),
    _ => ('$kind bị từ chối${r['decision_note'] == null ? '' : ': ${r['decision_note']}'}', Icons.cancel, AppColors.absentSoft,
        AppColors.absentText, AppColors.absentBorder),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
    child: Row(children: [
      Icon(icon, size: 14, color: fg),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg))),
    ]),
  );
}

/// Thẻ cảnh báo vắng nhiều của một lớp.
Widget absenceWarning(int absences, int limit) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.absentSoft, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.absentBorder)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.warning_amber_rounded, size: 21, color: AppColors.absentText),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(TextSpan(style: const TextStyle(fontSize: 13, height: 18 / 13, color: Color(0xFF881337)), children: [
            TextSpan(text: 'Bạn đã vắng $absences buổi. ', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: 'Từ $limit buổi trở lên là bị cảnh báo chuyên cần. '
                'Nếu có buổi nghỉ có lý do hoặc bị ghi vắng nhầm, hãy gửi đơn.'),
          ])),
        ),
      ]),
    );

/// Nhãn "Vắng N buổi" màu đỏ cho danh sách của giảng viên.
Widget absencePill(int n) => Pill('Vắng $n buổi', icon: Icons.warning_amber_rounded, bg: AppColors.absentSoft,
    fg: AppColors.absentText, border: AppColors.absentBorder, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2));
