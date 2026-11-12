import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../ui/neo_parts.dart';
import '../faces/face_review_page.dart';
import '../home/account_sheet.dart';

/// Dock nổi của giảng viên: Lớp / Duyệt mặt (có số chờ) / Đơn của sinh viên / Tài khoản.
NeoDock lecturerDock(BuildContext context, Session session, int current, {int? pending, int? requests}) => NeoDock(
      current: current,
      items: [
        const DockItem(Icons.class_, 'Lớp'),
        DockItem(Icons.how_to_reg_outlined, 'Duyệt mặt', badge: pending),
        DockItem(Icons.inbox_outlined, 'Đơn', badge: requests),
        const DockItem(Icons.badge_outlined, 'Tài khoản'),
      ],
      onTap: (i) {
        if (i == current) return;
        switch (i) {
          case 0:
            context.go('/lecturer');
          case 1:
            context.go('/lecturer/faces');
          case 2:
            context.go('/lecturer/requests');
          case 3:
            showAccountSheet(context, session);
        }
      },
    );

/// Tab "Duyệt mặt" trên điện thoại giảng viên.
class LecturerFacesPage extends StatefulWidget {
  const LecturerFacesPage({super.key, required this.session});
  final Session session;

  @override
  State<LecturerFacesPage> createState() => _LecturerFacesPageState();
}

class _LecturerFacesPageState extends State<LecturerFacesPage> {
  int? _count;

  @override
  Widget build(BuildContext context) => PhoneShell(
        header: const NeoHeader(label: 'Giảng viên', title: 'Duyệt khuôn mặt'),
        dock: lecturerDock(context, widget.session, 1, pending: _count),
        body: FaceReviewPage(session: widget.session, onCountChanged: (n) => setState(() => _count = n)),
      );
}
