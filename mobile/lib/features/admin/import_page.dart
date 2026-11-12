import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/api_error.dart';
import '../../core/files.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import 'admin_widgets.dart';

class _Kind {
  const _Kind(this.key, this.label, this.columns, this.sample);
  final String key;
  final String label;
  final String columns;
  final String sample;
}

const _kinds = [
  _Kind('users', 'Người dùng', 'role,username,email,full_name,student_code',
      'student,sv001,sv001@truong.edu.vn,Nguyễn Văn An,SV001\nlecturer,ducdm,,TS. Trần Minh Đức,\n'),
  _Kind('classes', 'Lớp', 'code,name,semester,lecturer_username', 'IT4060,Học máy,2026-1,ducdm\n'),
  _Kind('enrollments', 'Danh sách lớp', 'class_code,semester,student_code', 'IT4060,2026-1,SV001\n'),
];

/// Artboard "Web QTV · Nhập CSV" (Web_NhapCSV.dc.html). Chọn file → chạy thử (dry_run) → nhập. POST /admin/import.
class ImportPage extends StatefulWidget {
  const ImportPage({super.key, required this.session, this.pick = pickTextFile, this.download = downloadText});
  final Session session;
  final Future<PickedText?> Function() pick;
  final void Function(String name, String text) download;

  @override
  State<ImportPage> createState() => ImportPageState();
}

class ImportPageState extends State<ImportPage> {
  _Kind _kind = _kinds.first;
  PickedText? _file;
  Map<String, dynamic>? _check;
  Map<String, dynamic>? _done;
  bool _busy = false;
  String? _error;

  ApiClient get _api => widget.session.api;

  void downloadTemplate() => widget.download('mau_${_kind.key}.csv', '${_kind.columns}\n${_kind.sample}');

  Future<void> _choose() async {
    final f = await widget.pick();
    if (f == null) return;
    setState(() {
      _file = f;
      _done = null;
    });
    await _run(dryRun: true);
  }

  Future<void> _run({required bool dryRun}) async {
    if (_file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = Map<String, dynamic>.from(
          await _api.post('/admin/import', data: {'kind': _kind.key, 'dry_run': dryRun, 'csv_text': _file!.text}) as Map);
      if (mounted) setState(() => dryRun ? _check = r : _done = r);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() => setState(() {
        _file = null;
        _check = null;
        _done = null;
        _error = null;
      });

  void _downloadPasswords() {
    final rows = [for (final p in _done!['passwords'] as List) '${p['username']},${p['temp_password']}'];
    widget.download('mat_khau_tam.csv', 'username,temp_password\n${rows.join('\n')}\n');
  }

  @override
  Widget build(BuildContext context) {
    final check = _check;
    final errors = (check?['errors'] as List?) ?? const [];
    final step = _done != null ? 3 : _file != null ? 2 : 1;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: webContentMaxWidth),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const AdminHeading('Nhập dữ liệu từ CSV',
                subtitle: 'Hệ thống kiểm tra toàn bộ file trước. Có một dòng lỗi thì chưa nhập dòng nào.'),
            const SizedBox(height: 18),
            _Steps(current: step),
            const SizedBox(height: 20),
            NeoCard(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Loại dữ liệu', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
                const SizedBox(height: 10),
                LayoutBuilder(builder: (context, c) {
                  final w = c.maxWidth >= 700 ? (c.maxWidth - 24) / 3 : c.maxWidth;
                  return Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final k in _kinds) SizedBox(width: w, child: _kindCard(k)),
                  ]);
                }),
                const SizedBox(height: 16),
                _fileBox(),
              ]),
            ),
            if (_error != null) ...[const SizedBox(height: 16), ErrorNote(_error!)],
            if (_busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            if (check != null && _done == null && !_busy) ...[
              const SizedBox(height: 20),
              Wrap(spacing: 14, runSpacing: 14, children: [
                _stat('Tổng số dòng', check['total_rows'] as int, AppColors.text),
                _stat('Hợp lệ', (check['total_rows'] as int) - (check['error_rows'] as int), const Color(0xFF059669)),
                _stat('Có lỗi', check['error_rows'] as int, const Color(0xFFE11D48)),
              ]),
              if (errors.isNotEmpty) ...[const SizedBox(height: 20), _errorTable(errors)],
              const SizedBox(height: 20),
              Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 16, runSpacing: 10,
                  children: [
                    if (_kind.key == 'users')
                      const Text('Nhập xong, hệ thống tạo file mật khẩu tạm để phát cho từng người.',
                          style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
                    SizedBox(
                      height: 46,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        onPressed: check['ok'] == true && (check['created'] as int) > 0 ? () => _run(dryRun: false) : null,
                        child: Text('Nhập ${check['created'] > 0 ? check['created'] : check['total_rows']} dòng'),
                      ),
                    ),
                  ]),
            ],
            if (_done != null) ...[const SizedBox(height: 20), _doneCard()],
          ]),
        ),
      ),
    );
  }

  Widget _kindCard(_Kind k) {
    final active = k == _kind;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: active ? AppColors.primary : AppColors.inputBorder, width: active ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() {
            _kind = k;
            _check = null;
            _done = null;
          });
          _run(dryRun: true);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(active ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20,
                color: active ? AppColors.primary : AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)),
                const SizedBox(height: 2),
                Text(k.columns.replaceAll(',', ', '), style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _fileBox() {
    final f = _file;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: AppColors.presentSoft, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.description_outlined, size: 22, color: Color(0xFF059669)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: f == null
              ? const Text('Chưa chọn file CSV (UTF-8, dòng đầu là tên cột).',
                  style: TextStyle(fontSize: 14, color: AppColors.textMuted))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)),
                  Text(_size(f.size), style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                ]),
        ),
        OutlinedButton(
          style: adminOutlinedStyle(),
          onPressed: _busy ? null : _choose,
          child: Text(f == null ? 'Chọn file' : 'Chọn file khác'),
        ),
      ]),
    );
  }

  static String _size(int b) => b < 1024 ? '$b B' : '${(b / 1024).toStringAsFixed(b < 10240 ? 1 : 0)} KB';

  Widget _stat(String label, int value, Color color) => SizedBox(
        width: 240,
        child: NeoCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 4),
            Text('$value', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
          ]),
        ),
      );

  Widget _errorTable(List errors) => NeoCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            color: AppColors.absentSoft,
            child: Row(children: [
              const Icon(Icons.error_outline, size: 20, color: Color(0xFFE11D48)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Chưa nhập dòng nào. Sửa ${_check!['error_rows']} dòng lỗi rồi tải lại file.',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.absentText)),
              ),
            ]),
          ),
          _errRow(const Text('Dòng'), const Text('Cột'), const Text('Lỗi'), header: true),
          for (final e in errors)
            _errRow(
              Text('${e['line']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              e['col'] == null
                  ? const Text('–')
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: Pill('${e['col']}', bg: AppColors.cardBorder, fg: AppColors.textLabel, monospace: true,
                          radius: 6, fontSize: 12, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
                    ),
              Text('${e['msg']}'),
            ),
        ]),
      );

  Widget _errRow(Widget line, Widget col, Widget msg, {bool header = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: header ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.cardBorder))),
        child: DefaultTextStyle.merge(
          style: TextStyle(
              fontSize: 14,
              fontWeight: header ? FontWeight.w600 : null,
              color: header ? AppColors.textMuted : AppColors.text),
          child: Row(children: [
            SizedBox(width: 100, child: line),
            SizedBox(width: 160, child: col),
            Expanded(child: msg),
          ]),
        ),
      );

  Widget _doneCard() {
    final d = _done!;
    final hasPasswords = (d['passwords'] as List).isNotEmpty;
    return NeoCard(
      padding: const EdgeInsets.all(24),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: AppColors.presentSoft, borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.check_circle, size: 26, color: Color(0xFF059669)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Đã nhập ${d['created']} dòng ${_kind.label.toLowerCase()}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
            Text(
                hasPasswords
                    ? 'Tải file mật khẩu tạm ngay: hệ thống không lưu và không hiện lại các mật khẩu này.'
                    : 'Dữ liệu đã được ghi và lưu nhật ký.',
                style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
          ]),
        ),
        if (hasPasswords) ...[
          adminPrimaryButton('Tải file mật khẩu tạm', Icons.download, _downloadPasswords),
          const SizedBox(width: 10),
        ],
        OutlinedButton(style: adminOutlinedStyle(), onPressed: _reset, child: const Text('Nhập file khác')),
      ]),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    Widget step(int n, String label) {
      final done = n < current || current == 3;
      final active = n == current && !done;
      final color = done ? const Color(0xFF059669) : active ? AppColors.primary : AppColors.textMuted;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? const Color(0xFF059669) : active ? AppColors.primary : AppColors.inputBorder,
          ),
          child: done
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : Text('$n', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: active ? Colors.white : AppColors.textMuted)),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 14, fontWeight: active || done ? FontWeight.w600 : FontWeight.w500, color: color)),
      ]);
    }

    Widget line(bool done) => Container(
        width: 48, height: 2, margin: const EdgeInsets.symmetric(horizontal: 12),
        color: done ? const Color(0xFF059669) : AppColors.inputBorder);

    return Semantics(
      label: 'Bước $current trên 3',
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
        step(1, 'Chọn file'),
        line(current > 1),
        step(2, 'Kiểm tra'),
        line(current > 2),
        step(3, 'Nhập'),
      ]),
    );
  }
}
