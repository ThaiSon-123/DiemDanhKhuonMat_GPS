import 'package:flutter/material.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/app_text_field.dart';
import '../../ui/neo.dart';
import '../../ui/theme.dart';

/// Artboard "Chung · Đổi mật khẩu bắt buộc" (DoiMatKhau.dc.html).
/// [voluntary]: người dùng tự mở từ mục Tài khoản: có nút quay lại, đổi xong thì đóng màn.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key, required this.session, this.voluntary = false});
  final Session session;
  final bool voluntary;

  /// Mở màn tự đổi mật khẩu đè lên màn hiện tại.
  static Future<void> open(BuildContext context, Session session) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChangePasswordPage(session: session, voluntary: true)));

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

/// Độ mạnh 0–4 cho thước 4 vạch: đủ 8 ký tự, có số, có chữ hoa hoặc ký tự đặc biệt, từ 12 ký tự.
int passwordStrength(String p) => [
  p.length >= 8,
  RegExp(r'\d').hasMatch(p),
  RegExp(r'[A-Z]|[^A-Za-z0-9]').hasMatch(p),
  p.length >= 12,
].where((ok) => ok).length;

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _again = TextEditingController();
  String? _serverError;
  bool _submitted = false;
  bool _busy = false;

  bool get _longEnough => _new.text.length >= 8;
  bool get _differs => _new.text.isNotEmpty && _new.text != _old.text;
  bool get _matches => _new.text == _again.text;

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (!_longEnough || !_differs || !_matches) return;
    setState(() {
      _busy = true;
      _serverError = null;
    });
    try {
      await widget.session.changePassword(_old.text, _new.text);
      if (widget.voluntary && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Đã đổi mật khẩu. Các thiết bị khác đã bị đăng xuất.'), behavior: SnackBarBehavior.floating));
        Navigator.of(context).pop();
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _serverError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = passwordStrength(_new.text);
    final showMismatch = (_again.text.isNotEmpty || _submitted) && !_matches;
    void refresh(String _) => setState(() {});

    return NeoPage(
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: const Text('Lưu mật khẩu'),
          ),
          const SizedBox(height: 10),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.devices, size: 15, color: AppColors.textMuted),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Các thiết bị khác đang đăng nhập sẽ bị đăng xuất.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
      children: [
        if (widget.voluntary)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton.outlined(
              tooltip: 'Quay lại',
              style: IconButton.styleFrom(backgroundColor: Colors.white, side: const BorderSide(color: AppColors.cardBorder)),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back, size: 20, color: AppColors.textSecondary),
            ),
          ),
        HeroCard(
          emeraldGlow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0x336366F1),
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                  border: Border.fromBorderSide(
                    BorderSide(color: Color(0x4D818CF8)),
                  ),
                ),
                child: SizedBox.square(
                  dimension: 48,
                  child: Icon(
                    Icons.lock_reset,
                    size: 26,
                    color: Color(0xFFA5B4FC),
                  ),
                ),
              ),
              SizedBox(height: 12),
              Text(
                widget.voluntary ? 'Đổi mật khẩu' : 'Đặt mật khẩu mới',
                style: TextStyle(
                  fontSize: 24,
                  height: 30 / 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.48,
                ),
              ),
              SizedBox(height: 12),
              Text(
                widget.voluntary
                    ? 'Nhập mật khẩu đang dùng rồi đặt mật khẩu mới. Mật khẩu mới có hiệu lực ngay.'
                    : 'Bạn đang dùng mật khẩu tạm do khoa cấp. Hãy đặt mật khẩu của riêng bạn để tiếp tục.',
                style: TextStyle(
                  fontSize: 14,
                  height: 20 / 14,
                  color: AppColors.heroText,
                ),
              ),
            ],
          ),
        ),
        NeoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: widget.voluntary ? 'Mật khẩu hiện tại' : 'Mật khẩu tạm',
                controller: _old,
                obscure: true,
                onChanged: refresh,
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Mật khẩu mới',
                controller: _new,
                obscure: true,
                onChanged: refresh,
                below: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < 4; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Expanded(
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: i < strength
                                    ? AppColors.present
                                    : AppColors.cardBorder,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Rule(ok: _longEnough, text: 'Ít nhất 8 ký tự'),
                        _Rule(ok: _differs, text: widget.voluntary ? 'Khác mật khẩu cũ' : 'Khác mật khẩu tạm'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Nhập lại mật khẩu mới',
                controller: _again,
                obscure: true,
                onChanged: refresh,
                onSubmitted: (_) => _submit(),
                errorText: showMismatch
                    ? 'Hai mật khẩu chưa khớp'
                    : _serverError,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.ok, required this.text});
  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: ok ? AppColors.presentSoft : AppColors.inputFill,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: ok ? AppColors.presentBorder : AppColors.inputBorder,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 13,
          color: ok ? AppColors.presentText : AppColors.textMuted,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: ok ? AppColors.presentText : AppColors.textMuted,
          ),
        ),
      ],
    ),
  );
}
