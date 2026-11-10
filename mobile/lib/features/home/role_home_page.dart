import 'package:flutter/material.dart';

import '../../core/session.dart';

/// Khung trang chủ theo vai trò. Màn hình thật làm ở T10, T18, T19.
/// Màn hẹp (điện thoại): AppBar; màn rộng (web): thanh điều hướng bên trái.
class RoleHomePage extends StatelessWidget {
  const RoleHomePage({super.key, required this.session, required this.roleName});
  final Session session;
  final String roleName;

  @override
  Widget build(BuildContext context) {
    final name = session.user?['full_name'] ?? '';
    final body = Center(child: Text('Xin chào, $name\n($roleName)', textAlign: TextAlign.center));
    final logout = IconButton(tooltip: 'Đăng xuất', icon: const Icon(Icons.logout), onPressed: session.logout);

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 900) {
        return Scaffold(appBar: AppBar(title: Text(roleName), actions: [logout]), body: body);
      }
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        body: Row(children: [
          Container(
            width: 248,
            color: scheme.primary,
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Điểm danh', style: TextStyle(color: scheme.onPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
              Text(roleName, style: TextStyle(color: scheme.onPrimary)),
              const Spacer(),
              IconTheme(data: IconThemeData(color: scheme.onPrimary), child: logout),
            ]),
          ),
          Expanded(child: body),
        ]),
      );
    });
  }
}
