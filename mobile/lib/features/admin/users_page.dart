import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';

const _roles = {'student': 'Sinh viên', 'lecturer': 'Giảng viên', 'admin': 'Quản trị viên'};
const _faces = {'none': 'Chưa đăng ký', 'pending': 'Chờ duyệt', 'approved': 'Đã duyệt', 'rejected': 'Bị từ chối'};
const _avatars = [
  (Color(0xFFEEF2FF), Color(0xFF4F46E5)),
  (Color(0xFFECFDF5), Color(0xFF059669)),
  (Color(0xFFF5F3FF), Color(0xFF6D28D9)),
  (Color(0xFFFFFBEB), Color(0xFFB45309)),
  (Color(0xFFFFF1F2), Color(0xFFE11D48)),
];
const _pageSize = 20;

/// Artboard "Web QTV · Người dùng" (Web_NguoiDung.dc.html). Dữ liệu: GET /admin/users và các thao tác /admin/users/*.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key, required this.session});
  final Session session;

  @override
  State<UsersPage> createState() => UsersPageState();
}

class UsersPageState extends State<UsersPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String? _role;
  String? _face;
  int _page = 1;
  List<Map<String, dynamic>>? _items;
  int _total = 0;
  List<int>? _kpis;
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
    _search.dispose();
    super.dispose();
  }

  Future<int> _count(Map<String, dynamic> q) async => (await _api.get('/admin/users', query: {...q, 'size': 1}))['total'] as int;

  Future<void> _reload() async {
    setState(() => _error = null);
    try {
      final r = await Future.wait([
        _api.get('/admin/users', query: {
          'page': _page,
          'size': _pageSize,
          if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
          'role': ?_role,
          'face': ?_face,
        }),
        _count({'role': 'student'}),
        _count({'role': 'lecturer'}),
        _count({'role': 'student', 'face': 'none'}),
        _count({'active': false}),
      ]);
      if (!mounted) return;
      final list = r[0] as Map;
      setState(() {
        _items = [for (final u in list['items'] as List) Map<String, dynamic>.from(u as Map)];
        _total = list['total'] as int;
        _kpis = [for (final x in r.skip(1)) x as int];
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _filter(VoidCallback change) {
    setState(() {
      change();
      _page = 1;
    });
    _reload();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on ApiError catch (e) {
      _toast(e.message);
    }
  }

  // ---- Thao tác ----

  Future<void> addUser() async {
    final created = await showDialog<Map>(context: context, builder: (_) => _AddUserDialog(api: _api));
    if (created == null || !mounted) return;
    await _showTempPassword('${created['user']['username']}', '${created['temp_password']}');
    _reload();
  }

  Future<void> _resetPassword(Map<String, dynamic> u) async {
    final ok = await _confirm('Đặt lại mật khẩu cho ${u['full_name']}?',
        'Mật khẩu cũ và mọi phiên đăng nhập hiện tại sẽ mất hiệu lực. Người dùng phải đổi mật khẩu ở lần đăng nhập tới.',
        'Đặt lại');
    if (!ok) return;
    await _run(() async {
      final r = await _api.post('/admin/users/${u['id']}/reset-password');
      if (mounted) await _showTempPassword('${u['username']}', '${r['temp_password']}');
    });
  }

  Future<void> _toggleActive(Map<String, dynamic> u) async {
    final active = u['is_active'] == true;
    if (active) {
      final ok = await _confirm('Vô hiệu hóa ${u['full_name']}?',
          'Tài khoản bị đăng xuất khỏi mọi thiết bị và không đăng nhập được nữa. '
              'Dữ liệu khuôn mặt bị xóa ngay; kết quả điểm danh vẫn giữ.',
          'Vô hiệu hóa',
          danger: true);
      if (!ok) return;
    }
    await _run(() async {
      await _api.post('/admin/users/${u['id']}/${active ? 'deactivate' : 'activate'}');
      _toast(active ? 'Đã vô hiệu hóa ${u['full_name']}' : 'Đã bật lại ${u['full_name']}');
      _reload();
    });
  }

  Future<bool> _confirm(String title, String body, String action, {bool danger = false}) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            FilledButton(
              style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.absentText) : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _showTempPassword(String username, String temp) => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Mật khẩu tạm'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Gửi cho người dùng $username. Mật khẩu chỉ hiện một lần; lần đăng nhập đầu sẽ phải đổi.'),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: AppColors.inputFill, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.inputBorder)),
              child: SelectableText(temp, style: mono.copyWith(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 2)),
            ),
          ]),
          actions: [
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: temp)),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Sao chép'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Xong')),
          ],
        ),
      );

  // ---- Giao diện ----

  @override
  Widget build(BuildContext context) {
    if (_items == null) return LoadingOrError(error: _error, onRetry: _reload);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1116),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Người dùng',
                style: TextStyle(fontSize: 28, height: 36 / 28, fontWeight: FontWeight.w800, color: AppColors.text)),
            const SizedBox(height: 20),
            _kpiHero(),
            const SizedBox(height: 20),
            _table(),
          ]),
        ),
      ),
    );
  }

  Widget _kpiHero() {
    const labels = [
      ('Sinh viên', Color(0xFF818CF8)),
      ('Giảng viên', Color(0xFFA78BFA)),
      ('Chưa đăng ký khuôn mặt', Color(0xFFFBBF24)),
      ('Đã vô hiệu hóa', Color(0xFFFB7185)),
    ];
    return HeroCard(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / 212).floor().clamp(1, 4);
        final w = (c.maxWidth - 12 * (cols - 1)) / cols;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final (i, (label, dot)) in labels.indexed)
            Container(
              width: w,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0x66000000),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Flexible(child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)))),
                ]),
                const SizedBox(height: 4),
                Text('${_kpis?[i] ?? '–'}', style: mono.copyWith(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
              ]),
            ),
        ]);
      }),
    );
  }

  Widget _table() {
    final from = _total == 0 ? 0 : (_page - 1) * _pageSize + 1;
    final to = (_page - 1) * _pageSize + _items!.length;
    final pages = (_total / _pageSize).ceil().clamp(1, 1 << 30);
    return NeoCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 340,
              child: TextField(
                controller: _search,
                style: const TextStyle(fontSize: 14, color: AppColors.text),
                decoration: const InputDecoration(
                  hintText: 'Tên, tên đăng nhập hoặc mã sinh viên',
                  hintStyle: TextStyle(fontSize: 14, color: AppColors.textMuted),
                  prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textMuted),
                  isDense: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide(color: AppColors.inputBorder)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide(color: AppColors.focus, width: 2)),
                ),
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), () => _filter(() {}));
                },
              ),
            ),
            _Select(
              label: 'Vai trò',
              value: _role,
              options: {null: 'Mọi vai trò', ..._roles},
              onChanged: (v) => _filter(() => _role = v),
            ),
            _Select(
              label: 'Trạng thái khuôn mặt',
              value: _face,
              options: {null: 'Mọi trạng thái khuôn mặt', ..._faces},
              onChanged: (v) => _filter(() => _face = v),
            ),
          ]),
        ),
        const Divider(height: 1, color: AppColors.cardBorder),
        LayoutBuilder(builder: (context, c) {
          final table = SizedBox(
            width: c.maxWidth < 860 ? 860 : c.maxWidth,
            child: Column(children: [
              _row(const [
                Text('Người dùng'),
                Text('Vai trò'),
                Text('Khuôn mặt'),
                Text('Trạng thái'),
                Align(alignment: Alignment.centerRight, child: Text('Thao tác')),
              ], header: true),
              if (_items!.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Không có người dùng nào khớp bộ lọc.', style: TextStyle(color: AppColors.textMuted)),
                ),
              for (final (i, u) in _items!.indexed) _userRow(u, i),
            ]),
          );
          return SingleChildScrollView(scrollDirection: Axis.horizontal, child: table);
        }),
        const Divider(height: 1, color: AppColors.cardBorder),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(children: [
            Expanded(
              child: Text('Hiển thị $from–$to trong $_total người dùng',
                  style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
            ),
            _PageButton('Trước', onTap: _page > 1 ? () => setState(() => _page--) : null, after: _reload),
            const SizedBox(width: 6),
            for (final p in _pageWindow(_page, pages)) ...[
              _PageButton('$p', current: p == _page, onTap: () => setState(() => _page = p), after: _reload),
              const SizedBox(width: 6),
            ],
            _PageButton('Sau', onTap: _page < pages ? () => setState(() => _page++) : null, after: _reload),
          ]),
        ),
      ]),
    );
  }

  static List<int> _pageWindow(int page, int pages) {
    final start = (page - 1).clamp(1, (pages - 2).clamp(1, pages));
    return [for (var p = start; p <= pages && p < start + 3; p++) p];
  }

  static const _flex = [30, 16, 16, 14, 24];

  Widget _row(List<Widget> cells, {bool header = false}) {
    return Container(
      color: header ? AppColors.inputFill : null,
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: header ? 12 : 8),
      decoration: header ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.cardBorder))),
      child: DefaultTextStyle.merge(
        style: header
            ? const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted)
            : const TextStyle(fontSize: 14, color: AppColors.text),
        child: Row(children: [
          for (final (i, cell) in cells.indexed) Expanded(flex: _flex[i], child: cell),
        ]),
      ),
    );
  }

  Widget _userRow(Map<String, dynamic> u, int i) {
    final (bg, fg) = _avatars[i % _avatars.length];
    final active = u['is_active'] == true;
    final student = u['role'] == 'student';
    final face = '${u['face_status']}';
    final (faceBg, faceFg) = switch (face) {
      'approved' => (AppColors.presentSoft, const Color(0xFF059669)),
      'pending' => (const Color(0xFFFFFBEB), const Color(0xFFB45309)),
      'rejected' => (AppColors.absentSoft, const Color(0xFFE11D48)),
      _ => (AppColors.cardBorder, AppColors.textSecondary),
    };
    final name = '${u['full_name']}';
    return _row([
      Row(children: [
        InitialsAvatar(name, size: 38, round: true, bg: bg, fg: fg),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${u['username']}', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ]),
        ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_roles[u['role']] ?? '${u['role']}'),
        if (u['student_code'] != null)
          Text('${u['student_code']}', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ]),
      Align(
        alignment: Alignment.centerLeft,
        child: student
            ? Pill(_faces[face] ?? face, bg: faceBg, fg: faceFg, dot: true, fontSize: 13,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4))
            : const Text('Không áp dụng', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ),
      Text(active ? 'Hoạt động' : 'Vô hiệu hóa',
          style: TextStyle(fontWeight: FontWeight.w600, color: active ? const Color(0xFF059669) : const Color(0xFFE11D48))),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 36),
            foregroundColor: AppColors.text,
            side: const BorderSide(color: AppColors.inputBorder),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500),
          ),
          onPressed: () => _resetPassword(u),
          child: const Text('Đặt lại mật khẩu'),
        ),
        const SizedBox(width: 6),
        PopupMenuButton<String>(
          tooltip: 'Thêm thao tác cho $name',
          onSelected: (_) => _toggleActive(u),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'toggle',
              child: Text(active ? 'Vô hiệu hóa' : 'Bật lại tài khoản',
                  style: TextStyle(color: active ? AppColors.absentText : AppColors.text)),
            ),
          ],
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(border: Border.all(color: AppColors.inputBorder), borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.more_horiz, size: 18, color: AppColors.textSecondary),
          ),
        ),
      ]),
    ]);
  }
}

class _Select extends StatelessWidget {
  const _Select({required this.label, required this.value, required this.options, required this.onChanged});
  final String label;
  final String? value;
  final Map<String?, String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(border: Border.all(color: AppColors.inputBorder), borderRadius: BorderRadius.circular(10)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: value,
              borderRadius: BorderRadius.circular(12),
              style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.text),
              items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: onChanged,
            ),
          ),
        ),
      );
}

class _PageButton extends StatelessWidget {
  const _PageButton(this.text, {required this.onTap, required this.after, this.current = false});
  final String text;
  final VoidCallback? onTap;
  final VoidCallback after;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final style = current
        ? FilledButton.styleFrom(minimumSize: const Size(36, 36), padding: const EdgeInsets.symmetric(horizontal: 12),
            elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)))
        : OutlinedButton.styleFrom(minimumSize: const Size(36, 36), padding: const EdgeInsets.symmetric(horizontal: 12),
            foregroundColor: AppColors.text, side: const BorderSide(color: AppColors.inputBorder),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)));
    final tap = onTap == null || current
        ? null
        : () {
            onTap!();
            after();
          };
    return current
        ? FilledButton(style: style, onPressed: () {}, child: Text(text))
        : OutlinedButton(style: style, onPressed: tap, child: Text(text, style: const TextStyle(fontSize: 13)));
  }
}

class _AddUserDialog extends StatefulWidget {
  const _AddUserDialog({required this.api});
  final ApiClient api;

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  String _role = 'student';
  final _username = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _email = TextEditingController();
  Map<String, String> _errors = {};
  bool _busy = false;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      final r = await widget.api.post('/admin/users', data: {
        'role': _role,
        'username': _username.text,
        'full_name': _name.text,
        if (_role == 'student') 'student_code': _code.text,
        if (_email.text.trim().isNotEmpty) 'email': _email.text,
      });
      if (mounted) Navigator.pop(context, r as Map);
    } on ApiError catch (e) {
      final fieldErrors = {
        if (e.details is List)
          for (final d in e.details as List)
            if (d is Map) '${d['field']}': '${d['msg']}',
      };
      if (mounted) setState(() => _errors = fieldErrors.isEmpty ? {'_': e.message} : fieldErrors);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _deco(String label, String field) => InputDecoration(labelText: label, errorText: _errors[field]);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thêm người dùng'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: _deco('Vai trò', 'role'),
            items: [for (final e in _roles.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _role = v!),
          ),
          const SizedBox(height: 12),
          TextField(controller: _username, decoration: _deco('Tên đăng nhập', 'username')),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: _deco('Họ tên', 'full_name')),
          if (_role == 'student') ...[
            const SizedBox(height: 12),
            TextField(controller: _code, decoration: _deco('Mã sinh viên', 'student_code')),
          ],
          const SizedBox(height: 12),
          TextField(controller: _email, decoration: _deco('Email (không bắt buộc)', 'email')),
          if (_errors['_'] != null) ...[const SizedBox(height: 12), ErrorNote(_errors['_']!)],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Tạo tài khoản')),
      ],
    );
  }
}
