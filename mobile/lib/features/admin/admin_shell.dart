import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../ui/theme.dart';
import '../../ui/web_shell.dart';
import 'admin_widgets.dart';
import '../faces/face_review_page.dart';
import '../lecturer/report_page.dart';
import 'audit_page.dart';
import 'classes_page.dart';
import 'import_page.dart';
import 'overview_page.dart';
import 'users_page.dart';

const _nav = <WebNavItem>[
  WebNavItem('Bảng điều khiển', Icons.space_dashboard_outlined, 'Tổng quan'),
  WebNavItem('Quản lý', Icons.group_outlined, 'Người dùng'),
  WebNavItem('Quản lý', Icons.view_agenda_outlined, 'Lớp'),
  WebNavItem('Quản lý', Icons.upload_outlined, 'Nhập CSV'),
  WebNavItem('Giám sát', Icons.how_to_reg_outlined, 'Duyệt khuôn mặt'),
  WebNavItem('Giám sát', Icons.bar_chart, 'Báo cáo'),
  WebNavItem('Giám sát', Icons.list_alt, 'Nhật ký'),
];

/// Khung web quản trị theo các artboard Web_* : sidebar thẻ trắng nổi, đầu trang mờ kính có breadcrumb.
/// Màn hẹp hơn 900px: sidebar thành ngăn kéo.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.session});
  final Session session;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _current = 0;
  final _usersKey = GlobalKey<UsersPageState>();
  final _classesKey = GlobalKey<ClassesPageState>();
  final _importKey = GlobalKey<ImportPageState>();

  Widget? get _action => switch (_current) {
        1 => adminPrimaryButton('Thêm người dùng', Icons.add, () => _usersKey.currentState?.addUser()),
        2 => adminPrimaryButton('Thêm lớp', Icons.add, () => _classesKey.currentState?.addClass()),
        3 => TextButton.icon(
            onPressed: () => _importKey.currentState?.downloadTemplate(),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Tải file mẫu', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        _ => null,
      };

  Widget _page(String label) => switch (_current) {
        0 => OverviewPage(session: widget.session),
        1 => UsersPage(key: _usersKey, session: widget.session),
        2 => ClassesPage(key: _classesKey, session: widget.session),
        3 => ImportPage(key: _importKey, session: widget.session),
        4 => FaceReviewPage(session: widget.session),
        5 => ReportPage(session: widget.session),
        6 => AuditPage(session: widget.session),
        _ => Center(child: Text('Màn "$label" đang được xây dựng.', style: const TextStyle(color: AppColors.textMuted))),
      };

  @override
  Widget build(BuildContext context) {
    final item = _nav[_current];
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final sidebar = WebSidebar(
        session: widget.session,
        role: 'Quản trị',
        items: _nav,
        current: _current,
        onSelect: (i) {
          setState(() => _current = i);
          if (!wide) Navigator.of(context).maybePop();
        },
      );
      return Scaffold(
        drawer: wide ? null : Drawer(backgroundColor: AppColors.background, child: sidebar),
        body: SafeArea(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (wide) Padding(padding: const EdgeInsets.fromLTRB(16, 16, 0, 16), child: SizedBox(width: 256, child: sidebar)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                WebTopBar(
                  group: item.group,
                  title: item.label,
                  showMenu: !wide,
                  action: _action,
                ),
                Expanded(
                  child: _page(item.label),
                ),
              ]),
            ),
          ]),
        ),
      );
    });
  }
}
