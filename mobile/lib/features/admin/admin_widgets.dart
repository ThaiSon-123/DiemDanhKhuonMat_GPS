import 'package:flutter/material.dart';

import '../../core/api_error.dart';
import '../../ui/theme.dart';

/// Nút chính trên đầu trang web (canvas: cao 40, bo 10).
Widget adminPrimaryButton(String label, IconData icon, VoidCallback onPressed) => FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );

/// Nút viền nhỏ (bo 9, cao 36) dùng trong bảng và thanh công cụ.
ButtonStyle adminOutlinedStyle({Color fg = AppColors.text, Color border = AppColors.inputBorder}) =>
    OutlinedButton.styleFrom(
      minimumSize: const Size(0, 36),
      foregroundColor: fg,
      side: BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500),
    );

/// Tiêu đề trang web: h1 28/800 và dòng mô tả.
class AdminHeading extends StatelessWidget {
  const AdminHeading(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 28, height: 36 / 28, fontWeight: FontWeight.w800, color: AppColors.text)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: const TextStyle(fontSize: 15, color: AppColors.textMuted)),
        ],
      ]);
}

/// Ô chọn viền mảnh (canvas: cao 42–44, bo 10).
class AdminSelect<T> extends StatelessWidget {
  const AdminSelect({super.key, required this.label, required this.value, required this.options, required this.onChanged});
  final String label;
  final T? value;
  final Map<T?, String> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.inputBorder),
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T?>(
              value: value,
              borderRadius: BorderRadius.circular(12),
              style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.text),
              items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: onChanged,
            ),
          ),
        ),
      );
}

/// Ô nhập viền mảnh dùng trong thanh lọc (canvas: cao 42, bo 10, nền trắng).
InputDecoration adminFieldDecoration(String hint, {IconData? icon}) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 14, color: AppColors.textMuted),
      prefixIcon: icon == null ? null : Icon(icon, size: 18, color: AppColors.textMuted),
      isDense: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: AppColors.inputBorder)),
      focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: AppColors.focus, width: 2)),
    );

void adminToast(BuildContext context, String msg) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

/// Chạy một lệnh gọi API; lỗi thì hiện thông điệp của server.
Future<void> adminRun(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on ApiError catch (e) {
    if (context.mounted) adminToast(context, e.message);
  }
}

Future<bool> adminConfirm(BuildContext context, String title, String body, String action, {bool danger = false}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.absentText).merge(dialogButtonStyle) : dialogButtonStyle,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// Lỗi theo trường từ envelope 422 VALIDATION_ERROR; không có thì đặt vào khóa "_".
Map<String, String> fieldErrors(ApiError e) {
  final m = {
    if (e.details is List)
      for (final d in e.details as List)
        if (d is Map) '${d['field']}': '${d['msg']}',
  };
  return m.isEmpty ? {'_': e.message} : m;
}
