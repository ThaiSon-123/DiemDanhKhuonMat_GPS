import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import '../../ui/web_shell.dart';

const _nav = [
  (WebNavItem('Giảng dạy', Icons.schedule, 'Phiên điểm danh'), '/lecturer'),
  (WebNavItem('Giảng dạy', Icons.qr_code_2, 'Chiếu mã phòng'), '/lecturer/project'),
  (WebNavItem('Giảng dạy', Icons.how_to_reg_outlined, 'Duyệt khuôn mặt'), '/lecturer/faces'),
  (WebNavItem('Giảng dạy', Icons.bar_chart, 'Báo cáo'), '/lecturer/report'),
];

/// Khung giảng viên trên laptop (artboard Web_BaoCao, Web_ChieuMaPhong): màn ≥ 900 px có thanh bên "Giảng dạy",
/// trang con giữ bố cục của nó, dock điện thoại ẩn đi. Màn hẹp (điện thoại) trả nguyên trang con.
class LecturerShell extends StatelessWidget {
  const LecturerShell({super.key, required this.session, required this.location, required this.child});
  final Session session;
  final String location;
  final Widget child;

  int get _current {
    final i = _nav.indexWhere((e) => e.$2 != '/lecturer' && location.startsWith(e.$2));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 900) return child;
        return Scaffold(
          body: SafeArea(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                child: SizedBox(
                  width: 256,
                  child: WebSidebar(
                    session: session,
                    role: 'Giảng viên',
                    items: [for (final (it, _) in _nav) it],
                    current: _current,
                    onSelect: (i) => context.go(_nav[i].$2),
                  ),
                ),
              ),
              Expanded(child: InWebShell(child: child)),
            ]),
          ),
        );
      });
}

/// "Chiếu mã phòng" (đặc tả 4.7): chọn phiên đang mở có bật mã phòng rồi mở màn QR toàn màn hình.
class ProjectPickerPage extends StatefulWidget {
  const ProjectPickerPage({super.key, required this.session});
  final Session session;

  @override
  State<ProjectPickerPage> createState() => _ProjectPickerPageState();
}

class _ProjectPickerPageState extends State<ProjectPickerPage> {
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
      final r = await widget.session.api.get('/me/classes') as List;
      if (mounted) setState(() => _classes = [for (final c in r) Map<String, dynamic>.from(c as Map)]);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _classes?.where((c) => c['open_session'] != null).toList();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(children: [
              NeoHeader(label: 'Giảng dạy', title: 'Chiếu mã phòng', onBack: () => context.go('/lecturer')),
              Expanded(
                child: open == null
                    ? LoadingOrError(error: _error, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
                          const Text('Mở trên laptop nối máy chiếu. Mã đổi mỗi 30 giây; sinh viên quét hoặc gõ mã để xác nhận đúng phòng.',
                              style: TextStyle(fontSize: 13, height: 18 / 13, color: AppColors.textMuted)),
                          const SizedBox(height: 14),
                          if (open.isEmpty)
                            NeoCard(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                const Text('Chưa có phiên nào đang mở.',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
                                const SizedBox(height: 4),
                                const Text('Mở phiên (có bật mã phòng) ở mục Phiên điểm danh, rồi quay lại đây.',
                                    style: TextStyle(color: AppColors.textMuted)),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 18), label: const Text('Tải lại')),
                              ]),
                            ),
                          for (final c in open) ...[_row(c), const SizedBox(height: 10)],
                        ]),
                      ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> c) {
    final s = c['open_session'] as Map;
    final room = s['room_check'] == true;
    return NeoCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              CodeChip('${c['code']}'),
              CountdownPill(until: DateTime.parse('${s['expires_at']}').toLocal()),
            ]),
            const SizedBox(height: 6),
            Text('${c['name']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
            if (!room)
              const Text('Phiên này không bật mã phòng', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 44,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44), elevation: 0),
            onPressed: room ? () => context.push('/lecturer/session/${s['id']}/room') : null,
            icon: const Icon(Icons.qr_code_2, size: 18),
            label: const Text('Chiếu mã'),
          ),
        ),
      ]),
    );
  }
}
