import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ui/neo_parts.dart';

/// Dock nổi của sinh viên: Trang chủ / Lịch sử / Tài khoản.
NeoDock studentDock(BuildContext context, int current) => NeoDock(
      current: current,
      items: const [
        DockItem(Icons.home, 'Trang chủ'),
        DockItem(Icons.calendar_month, 'Lịch sử'),
        DockItem(Icons.badge_outlined, 'Tài khoản'),
      ],
      onTap: (i) {
        if (i == current) return;
        switch (i) {
          case 0:
            context.go('/student');
          case 1:
            comingSoon(context, 'Lịch sử chuyên cần');
          case 2:
            context.go('/student/face');
        }
      },
    );

/// Đi tới bước đăng ký phù hợp: chưa đồng ý văn bản hiện hành thì qua màn đồng ý trước.
void goEnroll(BuildContext context, Map<String, dynamic> me) =>
    context.go(me['consent']?['accepted'] == true ? '/student/enroll' : '/student/consent');
