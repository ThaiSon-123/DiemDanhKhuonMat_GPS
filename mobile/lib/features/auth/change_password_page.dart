import 'package:flutter/material.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/app_text_field.dart';
import '../../ui/brand_sheet_layout.dart';
import '../../ui/theme.dart';

/// Artboard "Chung · Đổi mật khẩu bắt buộc" (DoiMatKhau.dc.html).
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key, required this.session});
  final Session session;

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

    return BrandSheetLayout(
      header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: AppColors.primarySub, borderRadius: BorderRadius.circular(17)),
          child: const Icon(Icons.lock_outline, size: 28, color: Color(0xFFC7D2FE)),
        ),
        const SizedBox(height: 16),
        const Text('Đặt mật khẩu mới',
            style: TextStyle(fontSize: 26, height: 34 / 26, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(height: 16),
        const Text('Bạn đang dùng mật khẩu tạm do khoa cấp. Hãy đặt mật khẩu của riêng bạn để tiếp tục.',
            style: TextStyle(fontSize: 15, height: 22 / 15, color: AppColors.onPrimaryMuted)),
      ]),
      sheet: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(label: 'Mật khẩu tạm', controller: _old, obscure: true, onChanged: refresh),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Mật khẩu mới',
          controller: _new,
          obscure: true,
          onChanged: refresh,
          below: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < strength ? AppColors.present : AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 6, children: [
              _Rule(ok: _longEnough, text: 'Ít nhất 8 ký tự'),
              _Rule(ok: _differs, text: 'Khác mật khẩu tạm'),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Nhập lại mật khẩu mới',
          controller: _again,
          obscure: true,
          onChanged: refresh,
          onSubmitted: (_) => _submit(),
          errorText: showMismatch ? 'Hai mật khẩu chưa khớp' : _serverError,
        ),
        const Spacer(),
        const SizedBox(height: 24),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Lưu mật khẩu')),
        const SizedBox(height: 10),
        const Text('Các thiết bị khác đang đăng nhập sẽ bị đăng xuất.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ]),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.ok, required this.text});
  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.present : AppColors.textMuted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ok ? Icons.check : Icons.circle_outlined, size: 14, color: color),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontSize: 13, color: color)),
    ]);
  }
}
