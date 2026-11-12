import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import '../schedule.dart';
import 'admin_widgets.dart';

const _tiles = [
  (Color(0xFFEEF2FF), Color(0xFF4F46E5)),
  (Color(0xFFECFDF5), Color(0xFF059669)),
  (Color(0xFFF5F3FF), Color(0xFF6D28D9)),
  (Color(0xFFFFFBEB), Color(0xFFB45309)),
  (Color(0xFFFFF1F2), Color(0xFFE11D48)),
];

/// Chữ viết tắt tên lớp: chữ đầu tối đa 3 từ ("Học máy" → "HM").
String classShort(String name) => name
    .split(RegExp(r'[\s–-]+'))
    .where((w) => w.isNotEmpty)
    .take(3)
    .map((w) => w.characters.first)
    .join()
    .toUpperCase();

/// Artboard "Web QTV · Lớp" (Web_Lop.dc.html). Dữ liệu: /admin/classes, /admin/enrollments, /admin/users?role=lecturer.
class ClassesPage extends StatefulWidget {
  const ClassesPage({super.key, required this.session});
  final Session session;

  @override
  State<ClassesPage> createState() => ClassesPageState();
}

class ClassesPageState extends State<ClassesPage> {
  List<Map<String, dynamic>>? _classes;
  List<Map<String, dynamic>> _lecturers = [];
  List<Map<String, dynamic>>? _students;
  String? _semester;
  int? _selectedId;
  String? _error;
  final _addCode = TextEditingController();
  String? _addError;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addCode.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _list(Object r) => [
    for (final x in (r as Map)['items'] as List)
      Map<String, dynamic>.from(x as Map),
  ];

  Future<void> _load({int? select}) async {
    setState(() => _error = null);
    try {
      final r = await Future.wait([
        _api.get('/admin/classes', query: {'size': 200}),
        _api.get(
          '/admin/users',
          query: {'role': 'lecturer', 'active': true, 'size': 200},
        ),
      ]);
      if (!mounted) return;
      final classes = _list(r[0]);
      final semesters = {for (final c in classes) '${c['semester']}'};
      setState(() {
        _classes = classes;
        _lecturers = _list(r[1]);
        if (_semester == null || !semesters.contains(_semester)) {
          _semester = semesters.isEmpty ? null : semesters.first;
        }
        final visible = _visible;
        _selectedId =
            select ??
            (visible.any((c) => c['id'] == _selectedId)
                ? _selectedId
                : visible.firstOrNull?['id']);
      });
      await _loadStudents();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _loadStudents() async {
    if (_selectedId == null) return setState(() => _students = []);
    setState(() => _students = null);
    final r = await _api.get(
      '/admin/enrollments',
      query: {'class_id': _selectedId},
    );
    if (mounted) {
      setState(
        () => _students = [
          for (final s in r as List) Map<String, dynamic>.from(s as Map),
        ],
      );
    }
  }

  List<Map<String, dynamic>> get _visible => [
    for (final c in _classes ?? const [])
      if (c['semester'] == _semester) c,
  ];

  Map<String, dynamic>? get _selected =>
      _classes?.where((c) => c['id'] == _selectedId).firstOrNull;

  // ---- Thao tác ----

  Future<void> addClass() async {
    final id = await showDialog<int>(
      context: context,
      builder: (_) => _ClassDialog(
        api: _api,
        lecturers: _lecturers,
        semester: _semester ?? '',
      ),
    );
    if (id != null) _load(select: id);
  }

  Future<void> _edit(Map<String, dynamic> c) async {
    final result = await showDialog<Object>(
      context: context,
      builder: (_) => _ClassDialog(
        api: _api,
        lecturers: _lecturers,
        semester: '${c['semester']}',
        existing: c,
      ),
    );
    if (result == 'deleted') {
      _selectedId = null;
      _load();
    } else if (result != null) {
      _load(select: c['id'] as int);
    }
  }

  Future<void> _changeLecturer(Map<String, dynamic> c, int? lecturerId) async {
    if (lecturerId == null || lecturerId == c['lecturer_id']) return;
    await adminRun(context, () async {
      await _api.patch(
        '/admin/classes/${c['id']}',
        data: {'lecturer_id': lecturerId},
      );
      await _load(select: c['id'] as int);
    });
  }

  Future<void> _addStudent(Map<String, dynamic> c) async {
    final code = _addCode.text.trim();
    if (code.isEmpty) return;
    try {
      await _api.post(
        '/admin/enrollments',
        data: {'class_id': c['id'], 'student_code': code},
      );
      _addCode.clear();
      setState(() => _addError = null);
      await _load(select: c['id'] as int);
    } on ApiError catch (e) {
      if (mounted) setState(() => _addError = fieldErrors(e).values.first);
    }
  }

  Future<void> _removeStudent(
    Map<String, dynamic> c,
    Map<String, dynamic> s,
  ) async {
    final ok = await adminConfirm(
      context,
      'Xóa ${s['full_name']} khỏi lớp ${c['code']}?',
      'Kết quả điểm danh đã có của sinh viên trong lớp này vẫn được giữ.',
      'Xóa khỏi lớp',
      danger: true,
    );
    if (!ok || !mounted) return;
    await adminRun(context, () async {
      await _api.delete('/admin/enrollments/${c['id']}/${s['id']}');
      await _load(select: c['id'] as int);
    });
  }

  // ---- Giao diện ----

  @override
  Widget build(BuildContext context) {
    if (_classes == null) return LoadingOrError(error: _error, onRetry: _load);
    final sel = _selected;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: webContentMaxWidth),
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final listW = w >= 900 ? 300.0 : w;
              return SizedBox(
                width: w,
                child: Flex(
                  direction: w >= 900 ? Axis.horizontal : Axis.vertical,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: listW, child: _classList()),
                    const SizedBox(width: 20, height: 20),
                    if (w >= 900)
                      Expanded(child: _detail(sel))
                    else
                      _detail(sel),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _classList() {
    final semesters = {for (final c in _classes!) '${c['semester']}'};
    return NeoCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (semesters.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: AdminSelect<String>(
                label: 'Học kỳ',
                value: _semester,
                options: {for (final s in semesters) s: 'Học kỳ $s'},
                onChanged: (v) {
                  setState(() {
                    _semester = v;
                    _selectedId = _visible.firstOrNull?['id'];
                  });
                  _loadStudents();
                },
              ),
            ),
          if (_visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Chưa có lớp nào. Bấm "Thêm lớp" hoặc nhập CSV.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          for (final (i, c) in _visible.indexed) _classTile(c, i),
        ],
      ),
    );
  }

  Widget _classTile(Map<String, dynamic> c, int i) {
    final (bg, fg) = _tiles[i % _tiles.length];
    final active = c['id'] == _selectedId;
    return Material(
      color: active ? AppColors.primarySoft : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          setState(() => _selectedId = c['id'] as int);
          _addError = null;
          _loadStudents();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  classShort('${c['name']}'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c['name']}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    Text(
                      '${c['code']} · ${c['student_count']} SV · ${c['lecturer_name']}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(Map<String, dynamic>? c) {
    if (c == null) return const SizedBox.shrink();
    final students = _students;
    final approved = students
        ?.where((s) => s['face_status'] == 'approved')
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeoCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${c['name']}',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${c['code']} · Học kỳ ${c['semester']}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    style: adminOutlinedStyle(),
                    onPressed: () => _edit(c),
                    child: const Text('Sửa thông tin'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: _stat('Sinh viên', '${c['student_count']}')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _stat(
                      'Đã duyệt khuôn mặt',
                      approved == null ? '–' : '$approved',
                      color: const Color(0xFF059669),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _stat('Phiên đã điểm danh', '${c['session_count']}')),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Giảng viên phụ trách',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textLabel,
                ),
              ),
              const SizedBox(height: 6),
              AdminSelect<int>(
                label: 'Giảng viên phụ trách',
                value: _lecturers.any((l) => l['id'] == c['lecturer_id'])
                    ? c['lecturer_id'] as int
                    : null,
                options: {
                  for (final l in _lecturers)
                    l['id'] as int: '${l['full_name']} (${l['username']})',
                },
                onChanged: (v) => _changeLecturer(c, v),
              ),
              const SizedBox(height: 14),
              const Text(
                'Thêm sinh viên vào lớp',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textLabel,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addCode,
                      style: const TextStyle(fontSize: 14),
                      decoration: adminFieldDecoration('Mã sinh viên, vd SV120')
                          .copyWith(errorText: _addError),
                      onSubmitted: (_) => _addStudent(c),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 46,
                    child: adminPrimaryButton(
                      'Thêm',
                      Icons.person_add_alt,
                      () => _addStudent(c),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ScheduleEditor(key: ValueKey(c['id']), api: _api, classId: c['id'] as int),
        const SizedBox(height: 20),
        NeoCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Text(
                  'Danh sách sinh viên',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              Container(
                color: AppColors.inputFill,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
                child: const DefaultTextStyle(
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 5, child: Text('Sinh viên')),
                      Expanded(flex: 3, child: Text('Khuôn mặt')),
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text('Thao tác'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (students == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (students.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Lớp chưa có sinh viên.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                )
              else
                for (final (i, s) in students.indexed) _studentRow(c, s, i),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, {Color color = AppColors.text}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: mono.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      );

  Widget _studentRow(Map<String, dynamic> c, Map<String, dynamic> s, int i) {
    final (bg, fg) = _tiles[i % _tiles.length];
    final face = '${s['face_status']}';
    final (label, pbg, pfg) = switch (face) {
      'approved' => (
        'Đã duyệt',
        AppColors.presentSoft,
        const Color(0xFF059669),
      ),
      'pending' => (
        'Chờ duyệt',
        const Color(0xFFFFFBEB),
        const Color(0xFFB45309),
      ),
      'rejected' => (
        'Bị từ chối',
        AppColors.absentSoft,
        const Color(0xFFE11D48),
      ),
      _ => ('Chưa đăng ký', AppColors.cardBorder, AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                InitialsAvatar(
                  '${s['full_name']}',
                  size: 36,
                  round: true,
                  bg: bg,
                  fg: fg,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${s['full_name']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      Text(
                        '${s['student_code']}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Pill(
                label,
                bg: pbg,
                fg: pfg,
                dot: true,
                fontSize: 13,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE11D48),
                ),
                onPressed: () => _removeStudent(c, s),
                child: const Text(
                  'Xóa khỏi lớp',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thêm hoặc sửa lớp. Trả id lớp vừa lưu, hoặc "deleted" khi xóa.
class _ClassDialog extends StatefulWidget {
  const _ClassDialog({
    required this.api,
    required this.lecturers,
    required this.semester,
    this.existing,
  });
  final ApiClient api;
  final List<Map<String, dynamic>> lecturers;
  final String semester;
  final Map<String, dynamic>? existing;

  @override
  State<_ClassDialog> createState() => _ClassDialogState();
}

class _ClassDialogState extends State<_ClassDialog> {
  late final _code = TextEditingController(
    text: widget.existing?['code'] as String?,
  );
  late final _name = TextEditingController(
    text: widget.existing?['name'] as String?,
  );
  late final _semester = TextEditingController(text: widget.semester);
  late int? _lecturer =
      widget.existing?['lecturer_id'] as int? ??
      widget.lecturers.firstOrNull?['id'] as int?;
  Map<String, String> _errors = {};
  bool _busy = false;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      final body = {
        'code': _code.text,
        'name': _name.text,
        'semester': _semester.text,
        'lecturer_id': _lecturer,
      };
      final ex = widget.existing;
      final r = ex == null
          ? await widget.api.post('/admin/classes', data: body)
          : await widget.api.patch('/admin/classes/${ex['id']}', data: body);
      if (mounted) Navigator.pop(context, (r as Map)['id']);
    } on ApiError catch (e) {
      if (mounted) setState(() => _errors = fieldErrors(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ex = widget.existing!;
    final ok = await adminConfirm(
      context,
      'Xóa lớp ${ex['code']}?',
      'Danh sách sinh viên của lớp cũng bị xóa. Lớp đã có phiên điểm danh thì không xóa được.',
      'Xóa lớp',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await widget.api.delete('/admin/classes/${ex['id']}');
      if (mounted) Navigator.pop(context, 'deleted');
    } on ApiError catch (e) {
      if (mounted) setState(() => _errors = {'_': e.message});
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label, String f) =>
        InputDecoration(labelText: label, errorText: _errors[f]);
    return AlertDialog(
      title: Text(widget.existing == null ? 'Thêm lớp' : 'Sửa thông tin lớp'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _code,
              decoration: deco('Mã lớp học phần, vd IT4060', 'code'),
            ),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: deco('Tên lớp', 'name')),
            const SizedBox(height: 12),
            TextField(
              controller: _semester,
              decoration: deco('Học kỳ, vd 2026-1', 'semester'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _lecturer,
              decoration: deco('Giảng viên phụ trách', 'lecturer_id'),
              items: [
                for (final l in widget.lecturers)
                  DropdownMenuItem(
                    value: l['id'] as int,
                    child: Text('${l['full_name']} (${l['username']})'),
                  ),
              ],
              onChanged: (v) => setState(() => _lecturer = v),
            ),
            if (widget.lecturers.isEmpty) ...[
              const SizedBox(height: 12),
              const ErrorNote(
                'Chưa có giảng viên nào. Tạo tài khoản giảng viên trước.',
              ),
            ],
            if (_errors['_'] != null) ...[
              const SizedBox(height: 12),
              ErrorNote(_errors['_']!),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.absentText),
            onPressed: _busy ? null : _delete,
            child: const Text('Xóa lớp'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(style: dialogButtonStyle, onPressed: _busy ? null : _save, child: const Text('Lưu')),
      ],
    );
  }
}
