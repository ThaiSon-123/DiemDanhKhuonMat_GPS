import 'package:flutter/material.dart';

import 'theme.dart';

/// Ô nhập theo thiết kế: nhãn đậm phía trên, ô cao 50 bo 14, lỗi đỏ có biểu tượng ngay bên dưới.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.obscure = false,
    this.errorText,
    this.keyboardType,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.below,
  });

  final String label;
  final TextEditingController controller;
  final bool obscure;
  final String? errorText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Nội dung phụ dưới ô nhập (vd thước đo độ mạnh mật khẩu).
  final Widget? below;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

const _errorBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(14)),
  borderSide: BorderSide(color: AppColors.absent, width: 2),
);

class _AppTextFieldState extends State<AppTextField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ExcludeSemantics(
        child: Text(widget.label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
      ),
      const SizedBox(height: 6),
      Semantics(
        label: widget.label,
        child: TextField(
        controller: widget.controller,
        obscureText: _hidden,
        keyboardType: widget.keyboardType,
        autofillHints: widget.autofillHints,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        style: const TextStyle(fontSize: 16, color: AppColors.text),
        decoration: InputDecoration(
          fillColor: hasError ? Colors.white : null,
          enabledBorder: hasError ? _errorBorder : null,
          focusedBorder: hasError ? _errorBorder : null,
          suffixIcon: widget.obscure
              ? IconButton(
                  tooltip: _hidden ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                  color: AppColors.textMuted,
                  icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                  onPressed: () => setState(() => _hidden = !_hidden),
                )
              : null,
        ),
      )),
      if (widget.below != null) ...[const SizedBox(height: 8), widget.below!],
      if (hasError) ...[
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.error_outline, size: 16, color: AppColors.absent),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(widget.errorText!,
                style: const TextStyle(fontSize: 13, height: 19 / 13, color: AppColors.absent)),
          ),
        ]),
      ],
    ]);
  }
}
