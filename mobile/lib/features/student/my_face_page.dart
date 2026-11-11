import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import 'student_nav.dart';

/// Artboard "SV · Khuôn mặt của tôi" (SV_KhuonMatCuaToi.dc.html), cũng là tab Tài khoản. Dữ liệu: GET /me.
class MyFacePage extends StatefulWidget {
  const MyFacePage({super.key, required this.session});
  final Session session;

  @override
  State<MyFacePage> createState() => _MyFacePageState();
}

class _MyFacePageState extends State<MyFacePage> {
  Map<String, dynamic>? _me;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final me = Map<String, dynamic>.from(
        await widget.session.api.get('/me') as Map,
      );
      if (mounted) setState(() => _me = me);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa dữ liệu khuôn mặt?'),
        content: const Text(
          'Mẫu khuôn mặt và ảnh liên quan bị xóa ngay, không khôi phục được. '
          'Bạn sẽ không điểm danh bằng khuôn mặt được cho đến khi đăng ký lại; kết quả điểm danh cũ vẫn giữ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.absentText,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa dữ liệu'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.session.api.delete('/me/face');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã xóa dữ liệu khuôn mặt.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return PhoneShell(
      header: const NeoHeader(label: 'Điểm danh', title: 'Tài khoản'),
      dock: studentDock(context, 2),
      body: me == null
          ? LoadingOrError(error: _error, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  _profile(me),
                  const SizedBox(height: 12),
                  _faceHero(me),
                  const SizedBox(height: 12),
                  _rows(me),
                  const SizedBox(height: 12),
                  if (me['face']?['status'] != 'none')
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppColors.absentSoft,
                          foregroundColor: AppColors.absentText,
                          side: const BorderSide(color: AppColors.absentBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: _busy ? null : _delete,
                        icon: const Icon(Icons.delete_outline, size: 19),
                        label: const Text('Xóa dữ liệu khuôn mặt'),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    ErrorNote(_error!),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _profile(Map<String, dynamic> me) => NeoCard(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        InitialsAvatar('${me['full_name']}', size: 52),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${me['full_name']}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (me['student_code'] != null) ...[
                    CodeChip('${me['student_code']}'),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    '${me['username']}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Đăng xuất',
          onPressed: widget.session.logout,
          icon: const Icon(
            Icons.logout,
            size: 20,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );

  Widget _faceHero(Map<String, dynamic> me) {
    final f = (me['face'] as Map?) ?? const {};
    final status = '${f['status']}';
    final outdated = status == 'approved' && f['model_ok'] == false;
    final (
      glow,
      pillBg,
      pillBorder,
      pillFg,
      icon,
      title,
      sub,
      cta,
    ) = switch (status) {
      'approved' when outdated => (
        const Color(0x4DF59E0B),
        const Color(0x26F59E0B),
        const Color(0x4DF59E0B),
        const Color(0xFFFCD34D),
        Icons.update,
        'Cần đăng ký lại',
        'Hệ thống đã đổi mô hình nhận diện nên mẫu cũ không dùng được nữa.',
        'Đăng ký lại',
      ),
      'approved' => (
        const Color(0x4D10B981),
        const Color(0x2610B981),
        const Color(0x4D10B981),
        const Color(0xFF34D399),
        Icons.verified,
        'Đã duyệt',
        f['pending_update'] == true
            ? 'Mẫu mới đang chờ duyệt; mẫu hiện tại vẫn dùng để điểm danh cho đến khi mẫu mới được duyệt.'
            : 'Mẫu hợp lệ cho mọi lớp. Đăng ký lại khi diện mạo thay đổi nhiều.',
        f['pending_update'] == true ? null : 'Cập nhật khuôn mặt',
      ),
      'pending' => (
        const Color(0x4DF59E0B),
        const Color(0x26F59E0B),
        const Color(0x4DF59E0B),
        const Color(0xFFFCD34D),
        Icons.hourglass_top,
        'Đang chờ duyệt',
        'Bạn chưa điểm danh được cho đến khi giảng viên hoặc quản trị viên duyệt.',
        null,
      ),
      'rejected' => (
        const Color(0x4DF43F5E),
        const Color(0x26F43F5E),
        const Color(0x4DF43F5E),
        const Color(0xFFFB7185),
        Icons.cancel,
        'Bị từ chối',
        'Chụp lại theo lý do bên dưới rồi gửi lại.',
        'Đăng ký lại',
      ),
      _ => (
        const Color(0x594F46E5),
        const Color(0x336366F1),
        const Color(0x4D818CF8),
        const Color(0xFFA5B4FC),
        Icons.face_outlined,
        'Chưa đăng ký',
        'Đăng ký khuôn mặt một lần để điểm danh ở mọi lớp.',
        'Đăng ký khuôn mặt',
      ),
    };
    return HeroCard(
      glow: glow,
      emeraldGlow: false,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SINH TRẮC HỌC KHUÔN MẶT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
              Pill(
                title,
                icon: icon,
                bg: pillBg,
                fg: pillFg,
                border: pillBorder,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            sub,
            style: const TextStyle(
              fontSize: 13,
              height: 19 / 13,
              color: AppColors.heroText,
            ),
          ),
          if (status == 'rejected' && f['reject_reason'] != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x1FF43F5E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x4DF43F5E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Lý do từ chối',
                    style: TextStyle(fontSize: 11, color: Color(0xFFFDA4AF)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${f['reject_reason']}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFFE4E6),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (cta != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF020617),
                  elevation: 0,
                ),
                onPressed: () => goEnroll(context, me),
                icon: const Icon(
                  Icons.face_retouching_natural,
                  size: 19,
                  color: AppColors.primary,
                ),
                label: Text(cta),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _rows(Map<String, dynamic> me) {
    final c = (me['consent'] as Map?) ?? const {};
    final accepted = c['accepted'] == true;
    return NeoCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: _tile(
              Icons.verified_user_outlined,
              AppColors.primarySoft,
              AppColors.primary,
            ),
            title: const Text(
              'Văn bản đồng ý',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              accepted
                  ? 'Đã đồng ý ${c['current_version']}'
                  : 'Chưa đồng ý phiên bản ${c['current_version']}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            trailing: const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
            onTap: () => context.go('/student/consent'),
          ),
          const Divider(height: 1, color: AppColors.cardBorder),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: _tile(
              Icons.enhanced_encryption_outlined,
              AppColors.cardBorder,
              AppColors.textSecondary,
            ),
            title: const Text(
              'Dữ liệu hệ thống đang giữ',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Một vector đặc trưng đã mã hóa, không giữ ảnh gốc',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _tile(IconData icon, Color bg, Color fg) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, size: 19, color: fg),
  );
}
