import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import 'student_nav.dart';

/// Artboard "SV · Trang chủ" (SV_TrangChu.dc.html). Dữ liệu: GET /me, GET /me/classes.
/// Phần trăm chuyên cần từng lớp chờ GET /me/attendance (T16); phòng học, lịch học chưa có trong CSDL.
class StudentHomePage extends StatefulWidget {
  const StudentHomePage({super.key, required this.session});
  final Session session;

  @override
  State<StudentHomePage> createState() => _StudentHomePageState();
}

class _StudentHomePageState extends State<StudentHomePage> {
  Map<String, dynamic>? _me;
  List<Map<String, dynamic>>? _classes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final api = widget.session.api;
      final r = await Future.wait([api.get('/me'), api.get('/me/classes')]);
      if (!mounted) return;
      setState(() {
        _me = Map<String, dynamic>.from(r[0] as Map);
        _classes = [for (final c in r[1] as List) Map<String, dynamic>.from(c as Map)];
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return PhoneShell(
      header: NeoHeader(label: 'Điểm danh', title: 'Trang chủ', trailing: [
        HeaderTile(
          tooltip: 'Thông báo',
          onTap: () => comingSoon(context, 'Thông báo'),
          child: const Icon(Icons.notifications_none, size: 21, color: AppColors.textSecondary),
        ),
        if (me != null)
          InitialsAvatar('${me['full_name']}', verified: me['face']?['status'] == 'approved'),
      ]),
      dock: studentDock(context, 0),
      body: me == null || _classes == null
          ? LoadingOrError(error: _error, onRetry: _load)
          : RefreshIndicator(onRefresh: _load, child: _content(me, _classes!)),
    );
  }

  Widget _content(Map<String, dynamic> me, List<Map<String, dynamic>> classes) {
    final live = classes.where((c) => c['open_session'] != null).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
      children: [
        _GreetingCard(me: me, semester: classes.isEmpty ? null : '${classes.first['semester']}'),
        const SizedBox(height: 14),
        if (_enrollNote(me) case final note?) ...[_EnrollCard(note: note, onTap: () => goEnroll(context, me)), const SizedBox(height: 14)],
        if (live.isEmpty) const _NoSessionCard() else for (final c in live) ...[_LiveCard(c), const SizedBox(height: 14)],
        if (live.isEmpty) const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            const Text('Lớp học kỳ này', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(width: 8),
            Pill('${classes.length} môn', bg: AppColors.inputBorder, fg: AppColors.textLabel),
            const Spacer(),
            TextButton(
              onPressed: () => context.go('/student/history'),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Chuyên cần', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                Icon(Icons.chevron_right, size: 16),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        if (classes.isEmpty)
          const NeoCard(child: Text('Bạn chưa được thêm vào lớp nào.', style: TextStyle(color: AppColors.textMuted)))
        else
          for (final c in classes) ...[_ClassCard(c), const SizedBox(height: 10)],
      ],
    );
  }
}

/// Lời nhắc đăng ký khi chưa có mẫu dùng được để điểm danh; null khi mẫu đã duyệt và đúng mô hình.
(String, String)? _enrollNote(Map<String, dynamic> me) {
  final f = (me['face'] as Map?) ?? const {};
  return switch ('${f['status']}') {
    'approved' when f['model_ok'] == false => ('Cần đăng ký lại khuôn mặt', 'Hệ thống đã đổi mô hình nhận diện.'),
    'approved' || 'pending' => null,
    'rejected' => ('Đăng ký lại khuôn mặt', 'Ảnh lần trước bị từ chối: ${f['reject_reason'] ?? ''}'),
    _ => ('Đăng ký khuôn mặt', 'Cần làm một lần trước khi điểm danh. Mất khoảng 1 phút.'),
  };
}

class _EnrollCard extends StatelessWidget {
  const _EnrollCard({required this.note, required this.onTap});
  final (String, String) note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.face_retouching_natural, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(note.$1, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(note.$2, style: const TextStyle(fontSize: 12, height: 17 / 12, color: Color(0xFFE0E7FF))),
                ]),
              ),
              const Icon(Icons.arrow_forward, color: Colors.white),
            ]),
          ),
        ),
      );
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.me, required this.semester});
  final Map<String, dynamic> me;
  final String? semester;

  static const _face = {
    'approved': ('Khuôn mặt đã duyệt', Icons.verified_user, AppColors.presentSoft, AppColors.presentBorder, AppColors.presentText),
    'pending': ('Khuôn mặt chờ duyệt', Icons.hourglass_top, Color(0xFFFFFBEB), Color(0xFFFDE68A), Color(0xFF92400E)),
    'rejected': ('Khuôn mặt bị từ chối', Icons.cancel, AppColors.absentSoft, AppColors.absentBorder, AppColors.absentText),
    'none': ('Chưa đăng ký khuôn mặt', Icons.face_outlined, AppColors.cardBorder, AppColors.inputBorder, AppColors.textSecondary),
  };

  @override
  Widget build(BuildContext context) {
    final f = _face[me['face']?['status']] ?? _face['none']!;
    return NeoCard(
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (semester != null)
                Pill('Học kỳ $semester', bg: AppColors.primarySoft, fg: const Color(0xFF4338CA),
                    border: const Color(0xFFE0E7FF), dot: true),
              Pill(f.$1, icon: f.$2, bg: f.$3, border: f.$4, fg: f.$5),
            ]),
            const SizedBox(height: 6),
            Text('Xin chào, ${me['full_name']}!',
                style: const TextStyle(fontSize: 20, height: 26 / 20, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 6),
            if (me['student_code'] != null) CodeChip('${me['student_code']}'),
          ]),
        ),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: const Color(0x1A6366F1), borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.school, size: 24, color: Color(0xFF4338CA)),
        ),
      ]),
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard(this.c);
  final Map<String, dynamic> c;

  @override
  Widget build(BuildContext context) {
    final s = c['open_session'] as Map;
    return HeroCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 8, children: [
          const LivePill('Đang mở điểm danh'),
          CountdownPill(until: DateTime.parse('${s['expires_at']}').toLocal()),
        ]),
        const SizedBox(height: 14),
        Row(children: [CodeChip('${c['code']}', dark: true)]),
        const SizedBox(height: 6),
        Text('${c['name']}', style: const TextStyle(fontSize: 19, height: 25 / 19, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.person, size: 15, color: Color(0xFF818CF8)),
          const SizedBox(width: 4),
          Text('${c['lecturer_name']}', style: const TextStyle(fontSize: 12, color: AppColors.heroText)),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x0FFFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x1AFFFFFF)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Điều kiện điểm danh',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.heroText)),
            if (s['room_check'] == true) ...[
              const SizedBox(height: 8),
              const _Condition(icon: Icons.qr_code_scanner, tint: Color(0xFF34D399), bg: Color(0x3310B981),
                  title: 'Quét mã QR trên máy chiếu', sub: 'Mã đổi sau mỗi 30 giây'),
            ],
            const SizedBox(height: 8),
            const _Condition(icon: Icons.share_location, tint: Color(0xFF818CF8), bg: Color(0x336366F1),
                title: 'Ở trong phạm vi lớp học', sub: 'Độ chính xác GPS ≤ 30 m', subMono: true),
          ]),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF020617),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              shadowColor: Colors.white24,
            ),
            onPressed: () => context.go(Uri(path: '/student/checkin/${s['id']}',
                queryParameters: {'code': '${c['code']}', 'name': '${c['name']}'}).toString()),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.document_scanner_outlined, size: 20, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Điểm danh ngay'),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 18),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Condition extends StatelessWidget {
  const _Condition({required this.icon, required this.tint, required this.bg, required this.title, required this.sub,
      this.subMono = false});
  final IconData icon;
  final Color tint;
  final Color bg;
  final String title;
  final String sub;
  final bool subMono;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x66000000),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x0DFFFFFF)),
        ),
        child: Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 17, color: tint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.heroChipText)),
              Text(sub,
                  style: (subMono ? mono : const TextStyle())
                      .copyWith(fontSize: 11, color: subMono ? const Color(0xFF34D399) : const Color(0xFF94A3B8))),
            ]),
          ),
        ]),
      );
}

class _NoSessionCard extends StatelessWidget {
  const _NoSessionCard();

  @override
  Widget build(BuildContext context) => const NeoCard(
        padding: EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.event_available, size: 22, color: AppColors.textMuted),
          SizedBox(width: 12),
          Expanded(
            child: Text('Chưa có lớp nào đang mở điểm danh.',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          ),
        ]),
      );
}

class _ClassCard extends StatelessWidget {
  const _ClassCard(this.c);
  final Map<String, dynamic> c;

  @override
  Widget build(BuildContext context) => NeoCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CodeChip('${c['code']}'),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${c['lecturer_name']}',
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ),
          ]),
          const SizedBox(height: 4),
          Text('${c['name']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
        ]),
      );
}
