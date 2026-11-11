import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../ui/face_scan_icon.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';
import 'admin_widgets.dart';
import 'audit_page.dart';
import 'classes_page.dart';
import 'import_page.dart';
import 'users_page.dart';

class _NavItem {
  const _NavItem(this.group, this.icon, this.label);
  final String group;
  final IconData icon;
  final String label;
}

const _nav = [
  _NavItem('Quản lý', Icons.group_outlined, 'Người dùng'),
  _NavItem('Quản lý', Icons.view_agenda_outlined, 'Lớp'),
  _NavItem('Quản lý', Icons.upload_outlined, 'Nhập CSV'),
  _NavItem('Giám sát', Icons.how_to_reg_outlined, 'Duyệt khuôn mặt'),
  _NavItem('Giám sát', Icons.bar_chart, 'Báo cáo'),
  _NavItem('Giám sát', Icons.list_alt, 'Nhật ký'),
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
        0 => adminPrimaryButton('Thêm người dùng', Icons.add, () => _usersKey.currentState?.addUser()),
        1 => adminPrimaryButton('Thêm lớp', Icons.add, () => _classesKey.currentState?.addClass()),
        2 => TextButton.icon(
            onPressed: () => _importKey.currentState?.downloadTemplate(),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Tải file mẫu', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        _ => null,
      };

  Widget _page(String label) => switch (_current) {
        0 => UsersPage(key: _usersKey, session: widget.session),
        1 => ClassesPage(key: _classesKey, session: widget.session),
        2 => ImportPage(key: _importKey, session: widget.session),
        5 => AuditPage(session: widget.session),
        _ => Center(child: Text('Màn "$label" đang được xây dựng.', style: const TextStyle(color: AppColors.textMuted))),
      };

  @override
  Widget build(BuildContext context) {
    final item = _nav[_current];
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final sidebar = _Sidebar(
        session: widget.session,
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
                _TopBar(
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

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.session, required this.current, required this.onSelect});
  final Session session;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final u = session.user ?? const {};
    final name = '${u['full_name'] ?? ''}';
    final navWidgets = <Widget>[];
    for (final (i, it) in _nav.indexed) {
      if (i == 0 || _nav[i - 1].group != it.group) {
        navWidgets.add(Padding(
          padding: EdgeInsets.fromLTRB(12, i == 0 ? 0 : 14, 12, 6),
          child: Text(it.group.toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.9, color: Color(0xFF94A3B8))),
        ));
      }
      navWidgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: _NavTile(item: it, active: i == current, onTap: () => onSelect(i)),
      ));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 24, offset: Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: const FaceScanIcon(size: 22, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Điểm danh', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
              Text('Quản trị', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ]),
        ),
        const SizedBox(height: 28),
        ...navWidgets,
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.inputFill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(children: [
            InitialsAvatar(name, size: 36, round: true, bg: const Color(0xFFF5F3FF), fg: const Color(0xFF6D28D9)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
                Text('${u['username'] ?? ''}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
            ),
            IconButton(
              tooltip: 'Đăng xuất',
              onPressed: session.logout,
              icon: const Icon(Icons.logout, size: 19, color: AppColors.textSecondary),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.active, required this.onTap});
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textMuted;
    return Semantics(
      selected: active,
      child: Material(
        color: active ? AppColors.primarySoft : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Icon(item.icon, size: 20, color: color),
                const SizedBox(width: 12),
                Text(item.label,
                    style: TextStyle(fontSize: 14, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: color)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.group, required this.title, required this.showMenu, this.action});
  final String group;
  final String title;
  final bool showMenu;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: EdgeInsets.fromLTRB(showMenu ? 8 : 32, 10, 32, 10),
          decoration: const BoxDecoration(
            color: Color(0xD9F6F8FC),
            border: Border(bottom: BorderSide(color: Color(0x99E2E8F0))),
          ),
          child: Row(children: [
            if (showMenu)
              IconButton(
                tooltip: 'Mở menu',
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu, color: AppColors.textSecondary),
              ),
            Expanded(
              child: Text.rich(TextSpan(
                style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
                children: [
                  TextSpan(text: '$group / '),
                  TextSpan(text: title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
                ],
              )),
            ),
            ?action,
          ]),
        ),
      ),
    );
  }
}
