import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import 'lecturer_nav.dart';

/// Artboard "GV · Lớp của tôi" (GV_LopCuaToi.dc.html). Dữ liệu: GET /me/classes.
class LecturerHomePage extends StatefulWidget {
  const LecturerHomePage({super.key, required this.session});
  final Session session;

  @override
  State<LecturerHomePage> createState() => _LecturerHomePageState();
}

class _LecturerHomePageState extends State<LecturerHomePage> {
  List<Map<String, dynamic>>? _classes;
  int? _pending;
  int? _requests;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await widget.session.api.get('/me/classes');
      if (mounted) setState(() => _classes = [for (final c in r as List) Map<String, dynamic>.from(c as Map)]);
      final pending = await widget.session.api.get('/faces/pending') as List; // số trên tab "Duyệt mặt"
      if (mounted) setState(() => _pending = pending.length);
      final requests = await widget.session.api.get('/requests') as List; // đơn đang chờ: số trên tab "Đơn"
      if (mounted) setState(() => _requests = requests.length);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = '${widget.session.user?['full_name'] ?? ''}';
    return PhoneShell(
      header: NeoHeader(label: 'Giảng viên', title: 'Lớp của tôi', trailing: [
        InitialsAvatar(name, bg: const Color(0xFFFFFBEB), fg: const Color(0xFFB45309)),
      ]),
      dock: lecturerDock(context, widget.session, 0, pending: _pending, requests: _requests),
      body: _classes == null
          ? LoadingOrError(error: _error, onRetry: _load)
          : RefreshIndicator(onRefresh: _load, child: _content(name, _classes!)),
    );
  }

  Widget _content(String name, List<Map<String, dynamic>> classes) {
    final live = classes.where((c) => c['open_session'] != null).toList();
    final rest = classes.where((c) => c['open_session'] == null).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text.rich(TextSpan(
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            children: [
              TextSpan(text: vnDate(DateTime.now())),
              if (classes.isNotEmpty) TextSpan(text: ' · Học kỳ ${classes.first['semester']}'),
              const TextSpan(text: ' · '),
              TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
            ],
          )),
        ),
        const SizedBox(height: 14),
        for (final c in live) ...[_LiveClassCard(c), const SizedBox(height: 14)],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            const Text('Tất cả lớp', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(width: 8),
            Pill('${classes.length} lớp', bg: AppColors.inputBorder, fg: AppColors.textLabel),
          ]),
        ),
        const SizedBox(height: 14),
        if (classes.isEmpty)
          const NeoCard(child: Text('Bạn chưa được phân công lớp nào.', style: TextStyle(color: AppColors.textMuted)))
        else
          for (final c in rest) ...[_ClassCard(c), const SizedBox(height: 14)],
      ],
    );
  }
}

String _path(String page, Map c) =>
    Uri(path: '/lecturer/$page/${c['id']}', queryParameters: {'code': '${c['code']}', 'n': '${c['student_count']}'}).toString();

class _LiveClassCard extends StatelessWidget {
  const _LiveClassCard(this.c);
  final Map<String, dynamic> c;

  @override
  Widget build(BuildContext context) {
    final s = c['open_session'] as Map;
    return HeroCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 8, children: [
          const LivePill('Phiên đang mở'),
          CountdownPill(until: DateTime.parse('${s['expires_at']}').toLocal()),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          CodeChip('${c['code']}', dark: true),
          const SizedBox(width: 8),
          Text('${c['student_count']} SV', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        ]),
        const SizedBox(height: 4),
        Text('${c['name']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF020617),
              elevation: 0,
              textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700),
            ),
            onPressed: () => context.go('/lecturer/session/${s['id']}'),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Theo dõi phiên'),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 18),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _ClassCard extends StatelessWidget {
  const _ClassCard(this.c);
  final Map<String, dynamic> c;

  @override
  Widget build(BuildContext context) => NeoCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CodeChip('${c['code']}'),
            const SizedBox(width: 8),
            Text('${c['student_count']} SV', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
          const SizedBox(height: 4),
          Text('${c['name']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => context.go(_path('open', c)),
                  icon: const Icon(Icons.play_circle_outline, size: 17),
                  label: const Text('Mở phiên'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.inputFill,
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: AppColors.inputBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => context.go(_path('history', c)),
                  icon: const Icon(Icons.history, size: 17),
                  label: const Text('Lịch sử'),
                ),
              ),
            ),
          ]),
        ]),
      );
}
