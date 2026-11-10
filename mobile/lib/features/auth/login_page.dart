import 'package:flutter/material.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/app_text_field.dart';
import '../../ui/brand_sheet_layout.dart';
import '../../ui/face_scan_icon.dart';
import '../../ui/theme.dart';

/// Artboard "Đăng nhập" (Main.dc.html).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.session});
  final Session session;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.login(_email.text.trim(), _password.text);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandSheetLayout(
      header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          alignment: Alignment.center,
          child: const FaceScanIcon(size: 32, color: AppColors.primary),
        ),
        const SizedBox(height: 20),
        const Text('Điểm danh\nkhuôn mặt',
            style: TextStyle(fontSize: 30, height: 38 / 30, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(height: 8),
        const Text('Đúng người, đúng nơi, chỉ trong vài giây.',
            style: TextStyle(fontSize: 15, height: 22 / 15, color: AppColors.onPrimaryMuted)),
      ]),
      sheet: AutofillGroup(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Đăng nhập', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 18),
          AppTextField(
            label: 'Email trường',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Mật khẩu',
            controller: _password,
            obscure: true,
            errorText: _error,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Đang đăng nhập…' : 'Đăng nhập')),
          const Spacer(),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(14)),
            child: const Row(children: [
              Icon(Icons.help_outline, size: 20, color: AppColors.textMuted),
              SizedBox(width: 12),
              Expanded(
                child: Text('Quên mật khẩu? Liên hệ quản trị viên khoa để được cấp mật khẩu tạm.',
                    style: TextStyle(fontSize: 13, height: 19 / 13, color: AppColors.textSecondary)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
