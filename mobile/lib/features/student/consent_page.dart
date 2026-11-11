import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';

const _items = [
  (
    'Mục đích',
    'Chỉ dùng để xác nhận đúng người khi điểm danh ở các lớp bạn học.',
    Icons.track_changes,
    Color(0xFFEEF2FF),
    Color(0xFF4F46E5),
  ),
  (
    'Dữ liệu thu thập',
    'Ảnh khuôn mặt lúc đăng ký và điểm danh, vị trí GPS lúc điểm danh.',
    Icons.photo_camera_outlined,
    Color(0xFFF5F3FF),
    Color(0xFF7C3AED),
  ),
  (
    'Lưu bao lâu',
    'Ảnh đăng ký xóa ngay khi duyệt; ảnh lượt đáng ngờ giữ 30 ngày. Chỉ giữ dữ liệu đặc trưng đã mã hóa.',
    Icons.schedule,
    Color(0xFFFFFBEB),
    Color(0xFFB45309),
  ),
  (
    'Ai được xem',
    'Quản trị viên khoa và giảng viên lớp bạn. Mọi lượt xem ảnh đều ghi nhật ký.',
    Icons.visibility_outlined,
    Color(0xFFECFDF5),
    Color(0xFF047857),
  ),
  (
    'Quyền của bạn',
    'Xóa dữ liệu khuôn mặt bất cứ lúc nào trong mục Tài khoản.',
    Icons.delete_outline,
    Color(0xFFFFF1F2),
    Color(0xFFBE123C),
  ),
];

/// Artboard "SV · Đồng ý dữ liệu" (SV_DongY.dc.html). POST /me/consent với phiên bản hiện hành lấy từ GET /me.
class ConsentPage extends StatefulWidget {
  const ConsentPage({super.key, required this.session});
  final Session session;

  @override
  State<ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<ConsentPage> {
  String? _version;
  bool _accepted = false;
  bool _checked = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final me = await widget.session.api.get('/me') as Map;
      final c = me['consent'] as Map;
      if (mounted) {
        setState(() {
          _version = '${c['current_version']}';
          _accepted = c['accepted'] == true;
          _checked = _accepted;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_accepted) {
        await widget.session.api.post('/me/consent', data: {'version': _version});
      }
      if (mounted) context.go('/student/enroll');
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                NeoHeader(
                  label: 'Điểm danh',
                  title: 'Đồng ý dữ liệu',
                  onBack: () => context.go('/student'),
                ),
                Expanded(
                  child: _version == null
                      ? LoadingOrError(error: _error, onRetry: _load)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          children: [
                            HeroCard(
                              padding: const EdgeInsets.all(16),
                              emeraldGlow: false,
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: const Color(0x3310B981),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(
                                      Icons.verified_user,
                                      size: 26,
                                      color: Color(0xFF34D399),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Dữ liệu khuôn mặt của bạn',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Pill(
                                        'Văn bản $_version',
                                        bg: const Color(0x14FFFFFF),
                                        fg: AppColors.heroText,
                                        border: const Color(0x1FFFFFFF),
                                        monospace: true,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            for (final (title, body, icon, bg, fg)
                                in _items) ...[
                              const SizedBox(height: 10),
                              NeoCard(
                                radius: 20,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: bg,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(icon, size: 20, color: fg),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.text,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            body,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              height: 17 / 12,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
                if (_version != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: NeoCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CheckboxListTile(
                            value: _checked,
                            onChanged: _accepted
                                ? null
                                : (v) => setState(() => _checked = v ?? false),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Tôi đã đọc và đồng ý để hệ thống xử lý dữ liệu khuôn mặt của tôi cho việc điểm danh.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 18 / 13,
                                color: AppColors.textLabel,
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            ErrorNote(_error!),
                            const SizedBox(height: 8),
                          ],
                          FilledButton.icon(
                            onPressed: _checked && !_busy ? _submit : null,
                            iconAlignment: IconAlignment.end,
                            icon: const Icon(Icons.arrow_forward, size: 18),
                            label: Text(
                              _accepted
                                  ? 'Tiếp tục đăng ký khuôn mặt'
                                  : 'Đồng ý và tiếp tục',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
