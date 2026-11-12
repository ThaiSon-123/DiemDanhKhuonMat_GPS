import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import '../schedule.dart';

/// Một thông báo dựng từ dữ liệu sẵn có (/me, /me/classes, /me/attendance), không có bảng thông báo riêng.
class Notice {
  const Notice(this.icon, this.tint, this.bg, this.title, this.body, {this.at, this.route, this.urgent = false});
  final IconData icon;
  final Color tint;
  final Color bg;
  final String title;
  final String body;
  final DateTime? at;
  final String? route;

  /// Cần làm ngay (phiên đang mở, khuôn mặt bị từ chối): hiện chấm đỏ trên chuông.
  final bool urgent;
}

const _recent = Duration(days: 7);

List<Notice> buildNotices(Map<String, dynamic> me, List<Map<String, dynamic>> classes, List<Map<String, dynamic>> attendance,
    {List<Map<String, dynamic>> requests = const [], DateTime? now}) {
  final t = now ?? DateTime.now();
  final out = <Notice>[];
  for (final c in classes.where((c) => c['open_session'] != null)) {
    final s = c['open_session'] as Map;
    final route = Uri(path: '/student/checkin/${s['id']}', queryParameters: {'code': '${c['code']}', 'name': '${c['name']}'});
    final done = attendance.any((a) => a['session_id'] == s['id'] && a['status'] != 'absent');
    if (!done) {
      out.add(Notice(Icons.campaign, AppColors.absentText, AppColors.absentSoft, '${c['code']} đang mở điểm danh',
          '${c['name']} · đóng lúc ${_hhmm(s['expires_at'])}. Bấm để điểm danh ngay.',
          route: route.toString(), urgent: true));
    }
  }
  for (final c in classes.where((c) => c['warn'] == true)) {
    out.add(Notice(Icons.warning_amber_rounded, AppColors.absentText, AppColors.absentSoft, 'Cảnh báo chuyên cần ${c['code']}',
        'Bạn đã vắng ${c['absences']} buổi môn ${c['name']} (ngưỡng ${c['warn_absent']}). Buổi nghỉ có lý do thì gửi đơn.',
        route: '/student/history', urgent: true));
  }
  for (final r in requests.where((r) => r['decided_at'] != null)) {
    if (t.difference(DateTime.parse('${r['decided_at']}').toLocal()) > _recent) continue;
    final kind = r['kind'] == 'leave' ? 'Đơn xin nghỉ' : 'Khiếu nại';
    final ok = r['status'] == 'approved';
    out.add(Notice(ok ? Icons.check_circle : Icons.cancel, ok ? AppColors.presentText : AppColors.absentText,
        ok ? AppColors.presentSoft : AppColors.absentSoft, '$kind ${r['class_code']} ${ok ? 'được duyệt' : 'bị từ chối'}',
        ok ? (r['kind'] == 'leave' ? 'Buổi đó được ghi vắng có phép.' : 'Buổi đó được ghi có mặt.')
            : 'Lý do: ${r['decision_note'] ?? 'không ghi'}', route: '/student/history'));
  }
  for (final s in upcomingSlots(classes, now: t)) {
    if (s.cls['open_session'] != null) continue; // đã có thông báo "đang mở điểm danh"
    out.add(Notice(Icons.alarm, AppColors.primary, AppColors.primarySoft, 'Sắp đến giờ học ${s.cls['code']}',
        '${s.cls['name']} lúc ${s.start}${s.where}. Nhớ bật Wi-Fi, vị trí để điểm danh nhanh.', route: '/student'));
  }
  final face = me['face'] as Map?;
  switch (face?['status']) {
    case 'rejected':
      out.add(Notice(Icons.face_retouching_off, AppColors.absentText, AppColors.absentSoft, 'Ảnh khuôn mặt bị từ chối',
          '${face?['reject_reason'] ?? 'Hãy chụp lại theo hướng dẫn.'} Bấm để đăng ký lại.', route: '/student/face', urgent: true));
    case 'pending':
      out.add(const Notice(Icons.hourglass_top, Color(0xFFB45309), Color(0xFFFFFBEB), 'Khuôn mặt đang chờ duyệt',
          'Giảng viên sẽ duyệt ảnh đăng ký của bạn. Sau khi duyệt mới điểm danh được.', route: '/student/face'));
    case 'none':
      out.add(const Notice(Icons.face, AppColors.primary, AppColors.primarySoft, 'Chưa đăng ký khuôn mặt',
          'Cần đăng ký và được duyệt trước khi điểm danh.', route: '/student/face', urgent: true));
  }
  for (final a in attendance) {
    final at = DateTime.parse('${a['opened_at']}').toLocal();
    if (t.difference(at) > _recent) continue;
    final what = '${a['class_code']} · buổi ${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}';
    final n = switch (a['status']) {
      'suspicious' => Notice(Icons.hourglass_top, const Color(0xFFB45309), const Color(0xFFFFFBEB), 'Lượt điểm danh chờ duyệt',
          '$what: giảng viên sẽ xác nhận.', at: at, route: '/student/history'),
      'manual_present' => Notice(Icons.check_circle, AppColors.presentText, AppColors.presentSoft, 'Giảng viên xác nhận có mặt',
          what, at: at, route: '/student/history'),
      'excused' => Notice(Icons.description, AppColors.textLabel, const Color(0xFFF1F5F9), 'Được ghi vắng có phép', what,
          at: at, route: '/student/history'),
      'rejected' => Notice(Icons.cancel, AppColors.absentText, AppColors.absentSoft, 'Lượt điểm danh bị từ chối',
          '$what: giảng viên không chấp nhận lượt này.', at: at, route: '/student/history'),
      _ => null,
    };
    if (n != null) out.add(n);
  }
  return out;
}

String _hhmm(Object? iso) {
  final d = DateTime.parse('$iso').toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Nút chuông ở đầu trang, có chấm đỏ khi có việc cần làm ngay.
class NoticeBell extends StatelessWidget {
  const NoticeBell({super.key, required this.notices});
  final List<Notice>? notices;

  @override
  Widget build(BuildContext context) {
    final urgent = notices?.any((n) => n.urgent) ?? false;
    return Stack(clipBehavior: Clip.none, children: [
      HeaderTile(
        tooltip: 'Thông báo',
        onTap: notices == null ? null : () => showNotices(context, notices!),
        child: const Icon(Icons.notifications_none, size: 21, color: AppColors.textSecondary),
      ),
      if (urgent)
        Positioned(
          right: 8,
          top: 8,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: AppColors.absent, shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5)),
          ),
        ),
    ]);
  }
}

Future<void> showNotices(BuildContext context, List<Notice> notices) => showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 18, 16, 16), children: [
            Row(children: [
              const Expanded(
                child: Text('Thông báo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
              ),
              Pill('${notices.length}', bg: AppColors.inputBorder, fg: AppColors.textLabel),
            ]),
            const SizedBox(height: 14),
            if (notices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Text('Không có thông báo mới.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
              ),
            for (final n in notices) ...[
              Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: AppColors.cardBorder)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: n.route == null
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          context.go(n.route!);
                        },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(color: n.bg, borderRadius: BorderRadius.circular(14)),
                        child: Icon(n.icon, size: 21, color: n.tint),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(n.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                          const SizedBox(height: 2),
                          Text(n.body, style: const TextStyle(fontSize: 13, height: 18 / 13, color: AppColors.textSecondary)),
                        ]),
                      ),
                      if (n.route != null) const Icon(Icons.chevron_right, size: 20, color: Color(0xFF94A3B8)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ]),
        ),
      ),
    );
