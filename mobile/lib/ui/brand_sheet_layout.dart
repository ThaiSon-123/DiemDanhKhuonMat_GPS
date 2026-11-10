import 'package:flutter/material.dart';

import 'theme.dart';

/// Bố cục chung của Đăng nhập / Đổi mật khẩu (artboard Main, DoiMatKhau):
/// nửa trên indigo có vòng tròn trang trí, form trên tấm trắng bo góc 28 phía trên.
/// Màn rộng (web): giữ khổ điện thoại 480px ở giữa nền indigo.
class BrandSheetLayout extends StatelessWidget {
  const BrandSheetLayout({super.key, required this.header, required this.sheet});
  final Widget header;
  final Widget sheet;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(children: [
        Positioned(right: -90, top: -70, child: _ring(300)),
        Positioned(right: -30, top: -10, child: _ring(180)),
        SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Padding(padding: const EdgeInsets.fromLTRB(28, 72, 28, 36), child: header),
                        Expanded(
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                            ),
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                            child: sheet,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  static Widget _ring(double d) => IgnorePointer(
        child: Container(
          width: d,
          height: d,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.primaryDark)),
        ),
      );
}
