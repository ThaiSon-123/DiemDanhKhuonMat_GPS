import 'package:flutter/material.dart';

import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/app_text_field.dart';
import '../../ui/face_scan_icon.dart';
import '../../ui/neo.dart';
import '../../ui/theme.dart';

/// Artboard "Đăng nhập" (Main.dc.html).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.session});
  final Session session;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.login(_username.text.trim(), _password.text);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NeoPage(
      bottom: const NeoCard(
        radius: 20,
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: SizedBox.square(
                dimension: 36,
                child: Icon(
                  Icons.help_outline,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Quên mật khẩu? Liên hệ quản trị viên khoa để được cấp mật khẩu tạm.',
                style: TextStyle(
                  fontSize: 12,
                  height: 17 / 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0F0F172A),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const FaceScanIcon(size: 24, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ĐIỂM DANH',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    'Khuôn mặt + GPS',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const HeroCard(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Điểm danh\ntrong vài giây',
                style: TextStyle(
                  fontSize: 28,
                  height: 34 / 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.56,
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Đúng người bằng khuôn mặt, đúng nơi bằng GPS.',
                style: TextStyle(
                  fontSize: 14,
                  height: 20 / 14,
                  color: AppColors.heroText,
                ),
              ),
              SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HeroChip(
                    icon: Icons.face_outlined,
                    color: Color(0xFF818CF8),
                    text: 'Khuôn mặt',
                  ),
                  _HeroChip(
                    icon: Icons.share_location,
                    color: Color(0xFF34D399),
                    text: 'Vị trí',
                  ),
                  _HeroChip(
                    icon: Icons.qr_code_scanner,
                    color: Color(0xFFFBBF24),
                    text: 'Mã phòng',
                  ),
                ],
              ),
            ],
          ),
        ),
        NeoCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Đăng nhập',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: 'Tên đăng nhập',
                  icon: Icons.person_outline,
                  controller: _username,
                  keyboardType: TextInputType.visiblePassword,
                  autofillHints: const [AutofillHints.username],
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: 'Mật khẩu',
                  icon: Icons.lock_outline,
                  controller: _password,
                  obscure: true,
                  errorText: _error,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text(_busy ? 'Đang đăng nhập…' : 'Đăng nhập'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({
    required this.icon,
    required this.color,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0x0FFFFFFF),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0x1AFFFFFF)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: AppColors.heroChipText),
        ),
      ],
    ),
  );
}
