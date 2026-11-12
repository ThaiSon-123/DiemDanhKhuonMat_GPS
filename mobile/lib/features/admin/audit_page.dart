import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import 'admin_widgets.dart';

/// Nhóm hành động cho bộ lọc (backend lọc theo tiền tố khi giá trị kết thúc bằng ".").
const _groups = {
  'user.': 'Tài khoản',
  'class.': 'Lớp',
  'enrollment.': 'Danh sách lớp',
  'import.': 'Nhập CSV',
  'face.': 'Khuôn mặt',
  'record.': 'Chỉnh kết quả',
  'evidence.': 'Xem ảnh bằng chứng',
  'report.': 'Xuất báo cáo',
};

/// action → (động từ, biểu tượng, nền ô, màu biểu tượng).
const _verbs = <String, (String, IconData, Color, Color)>{
  'user.create': ('tạo tài khoản', Icons.person_add_alt, Color(0xFFEEF2FF), Color(0xFF4F46E5)),
  'user.update': ('sửa thông tin của', Icons.edit_outlined, Color(0xFFEEF2FF), Color(0xFF4F46E5)),
  'user.reset_password': ('đặt lại mật khẩu của', Icons.key_outlined, Color(0xFFFFFBEB), Color(0xFFB45309)),
  'user.deactivate': ('vô hiệu hóa', Icons.block, Color(0xFFFFF1F2), Color(0xFFE11D48)),
  'user.activate': ('bật lại tài khoản', Icons.check_circle_outline, Color(0xFFECFDF5), Color(0xFF059669)),
  'user.delete': ('xóa tài khoản', Icons.delete_outline, Color(0xFFFFF1F2), Color(0xFFE11D48)),
  'face.delete': ('xóa dữ liệu khuôn mặt của', Icons.delete_outline, Color(0xFFFFF1F2), Color(0xFFE11D48)),
  'face.review': ('duyệt khuôn mặt của', Icons.check, Color(0xFFECFDF5), Color(0xFF059669)),
  'face.enroll': ('gửi ảnh đăng ký khuôn mặt', Icons.face_outlined, Color(0xFFEEF2FF), Color(0xFF4F46E5)),
  'face.photos.view': ('xem ảnh đăng ký', Icons.visibility_outlined, Color(0xFFF1F5F9), Color(0xFF475569)),
  'class.create': ('tạo lớp', Icons.add_box_outlined, Color(0xFFF5F3FF), Color(0xFF6D28D9)),
  'class.update': ('sửa lớp', Icons.edit_outlined, Color(0xFFF5F3FF), Color(0xFF6D28D9)),
  'class.delete': ('xóa lớp', Icons.delete_outline, Color(0xFFFFF1F2), Color(0xFFE11D48)),
  'enrollment.add': ('thêm vào lớp', Icons.group_add_outlined, Color(0xFFF1F5F9), Color(0xFF475569)),
  'enrollment.remove': ('xóa khỏi lớp', Icons.group_remove_outlined, Color(0xFFF1F5F9), Color(0xFF475569)),
  'import.users': ('nhập CSV', Icons.upload_outlined, Color(0xFFF5F3FF), Color(0xFF6D28D9)),
  'import.classes': ('nhập CSV', Icons.upload_outlined, Color(0xFFF5F3FF), Color(0xFF6D28D9)),
  'import.enrollments': ('nhập CSV', Icons.upload_outlined, Color(0xFFF5F3FF), Color(0xFF6D28D9)),
  'record.update': ('chỉnh kết quả của', Icons.edit_outlined, Color(0xFFEEF2FF), Color(0xFF4F46E5)),
  'evidence.view': ('xem ảnh bằng chứng của', Icons.visibility_outlined, Color(0xFFF1F5F9), Color(0xFF475569)),
  'report.export': ('xuất báo cáo', Icons.download_outlined, Color(0xFFF5F3FF), Color(0xFF6D28D9)),
};

const _pageSize = 50;

/// Artboard "Web QTV · Nhật ký" (Web_NhatKy.dc.html). Dữ liệu: GET /admin/audit-log.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key, required this.session});
  final Session session;

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  final _actor = TextEditingController();
  Timer? _debounce;
  String? _group;
  DateTime? _from;
  DateTime? _to;
  List<Map<String, dynamic>>? _items;
  int _total = 0;
  int _page = 1;
  bool _loadingMore = false;
  String? _error;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _actor.dispose();
    super.dispose();
  }

  Future<Map> _fetch(int page) async => await _api.get('/admin/audit-log', query: {
        'page': page,
        'size': _pageSize,
        if (_actor.text.trim().isNotEmpty) 'actor': _actor.text.trim(),
        'action': ?_group,
        if (_from != null) 'from': _from!.toUtc().toIso8601String(),
        if (_to != null) 'to': _to!.add(const Duration(days: 1)).toUtc().toIso8601String(),
      }) as Map;

  Future<void> _reload() async {
    setState(() {
      _error = null;
      _page = 1;
    });
    try {
      final r = await _fetch(1);
      if (mounted) {
        setState(() {
          _items = [for (final x in r['items'] as List) Map<String, dynamic>.from(x as Map)];
          _total = r['total'] as int;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _more() async {
    setState(() => _loadingMore = true);
    await adminRun(context, () async {
      final r = await _fetch(_page + 1);
      if (mounted) {
        setState(() {
          _page++;
          _items!.addAll([for (final x in r['items'] as List) Map<String, dynamic>.from(x as Map)]);
        });
      }
    });
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (d == null) return;
    setState(() => from ? _from = d : _to = d);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: webContentMaxWidth),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const AdminHeading('Nhật ký thao tác',
                subtitle: 'Xem ảnh, duyệt khuôn mặt, chỉnh kết quả, xuất báo cáo và xóa dữ liệu đều được ghi lại tại đây.'),
            const SizedBox(height: 20),
            NeoCard(
              padding: const EdgeInsets.all(16),
              child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _actor,
                    style: const TextStyle(fontSize: 14),
                    decoration: adminFieldDecoration('Người thực hiện', icon: Icons.search),
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 350), _reload);
                    },
                  ),
                ),
                AdminSelect<String>(
                  label: 'Hành động',
                  value: _group,
                  options: {null: 'Mọi hành động', ..._groups},
                  onChanged: (v) {
                    setState(() => _group = v);
                    _reload();
                  },
                ),
                _dateButton('Từ ngày', _from, () => _pickDate(true)),
                const Text('→', style: TextStyle(color: AppColors.textMuted)),
                _dateButton('Đến ngày', _to, () => _pickDate(false)),
                if (_from != null || _to != null)
                  TextButton(
                    onPressed: () {
                      setState(() => _from = _to = null);
                      _reload();
                    },
                    child: const Text('Bỏ lọc ngày'),
                  ),
              ]),
            ),
            const SizedBox(height: 20),
            if (_items == null)
              SizedBox(height: 200, child: LoadingOrError(error: _error, onRetry: _reload))
            else if (_items!.isEmpty)
              const NeoCard(child: Text('Không có thao tác nào khớp bộ lọc.', style: TextStyle(color: AppColors.textMuted)))
            else ...[
              ..._days(),
              if (_items!.length < _total)
                Center(
                  child: OutlinedButton(
                    style: adminOutlinedStyle(),
                    onPressed: _loadingMore ? null : _more,
                    child: Text('Tải thêm (${_total - _items!.length})'),
                  ),
                ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _dateButton(String label, DateTime? d, VoidCallback onTap) => OutlinedButton.icon(
        style: adminOutlinedStyle().copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 44))),
        onPressed: onTap,
        icon: const Icon(Icons.calendar_today_outlined, size: 16),
        label: Text(d == null ? label : _dmy(d)),
      );

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _dmy(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

  List<Widget> _days() {
    final groups = <DateTime, List<Map<String, dynamic>>>{};
    for (final it in _items!) {
      final t = DateTime.parse('${it['created_at']}').toLocal();
      groups.putIfAbsent(DateTime(t.year, t.month, t.day), () => []).add(it);
    }
    final today = DateTime.now();
    final d0 = DateTime(today.year, today.month, today.day);
    return [
      for (final e in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            (e.key == d0 ? 'Hôm nay · ' : e.key == d0.subtract(const Duration(days: 1)) ? 'Hôm qua · ' : '').toUpperCase() +
                _dmy(e.key),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.textMuted),
          ),
        ),
        NeoCard(
          padding: EdgeInsets.zero,
          child: Column(children: [for (final (i, it) in e.value.indexed) _entry(it, first: i == 0)]),
        ),
        const SizedBox(height: 20),
      ],
    ];
  }

  Widget _entry(Map<String, dynamic> it, {required bool first}) {
    final action = '${it['action']}';
    final (verb, icon, bg, fg) = _verbs[action] ?? (action, Icons.history, AppColors.cardBorder, AppColors.textSecondary);
    final t = DateTime.parse('${it['created_at']}').toLocal();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.cardBorder))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, size: 18, color: fg),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(style: const TextStyle(fontSize: 15, color: AppColors.text), children: [
              TextSpan(text: '${it['actor_name'] ?? 'Hệ thống'}', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' $verb '),
              TextSpan(text: _target(it), style: const TextStyle(fontWeight: FontWeight.w700)),
            ])),
            if (_detail(it) case final d?) ...[
              const SizedBox(height: 2),
              Text(d, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
            ],
          ]),
        ),
        const SizedBox(width: 12),
        Text('${_two(t.hour)}:${_two(t.minute)}', style: mono.copyWith(fontSize: 13, color: AppColors.textMuted)),
      ]),
    );
  }

  /// Tên đối tượng: tên server tra được; người/lớp đã xóa thì lấy từ dữ liệu "before".
  static String _target(Map<String, dynamic> it) {
    final before = it['before'] as Map?;
    final after = it['after'] as Map?;
    final action = '${it['action']}';
    if (action.startsWith('import.')) {
      return const {'import.users': 'người dùng', 'import.classes': 'lớp'}[action] ?? 'danh sách lớp';
    }
    return '${it['target_name'] ?? before?['full_name'] ?? before?['code'] ?? after?['code'] ?? it['target']}';
  }

  static String? _detail(Map<String, dynamic> it) {
    final after = it['after'] as Map?;
    final before = it['before'] as Map?;
    if (after?['created'] != null) return '${after!['created']} dòng';
    if (after?['faces_revoked'] != null) return 'Thu hồi ${after!['faces_revoked']} mẫu khuôn mặt';
    if (before != null && after != null) {
      final changed = [for (final k in after.keys) if (before[k] != after[k]) '$k: ${before[k] ?? '–'} → ${after[k] ?? '–'}'];
      return changed.isEmpty ? null : changed.join(' · ');
    }
    if ('${it['target']}'.startsWith('enrollments:')) return 'Lớp #${'${it['target']}'.split(':')[1]}';
    return null;
  }
}
