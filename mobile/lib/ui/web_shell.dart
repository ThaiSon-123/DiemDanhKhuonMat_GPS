import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/session.dart';
import '../features/auth/change_password_page.dart';
import 'face_scan_icon.dart';
import 'neo_parts.dart';
import 'theme.dart';

/// Một mục của thanh bên web (artboard Web_*).
class WebNavItem {
  const WebNavItem(this.group, this.icon, this.label, {this.badge});
  final String group;
  final IconData icon;
  final String label;
  final int? badge;
}

/// Đánh dấu nội dung đang nằm trong khung web có thanh bên: [PhoneShell] ẩn dock điện thoại.
class InWebShell extends InheritedWidget {
  const InWebShell({super.key, required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<InWebShell>() != null;

  @override
  bool updateShouldNotify(InWebShell oldWidget) => false;
}

/// Thanh bên thẻ trắng nổi: logo + vai trò, các nhóm mục, thẻ người dùng (đổi mật khẩu, đăng xuất).
class WebSidebar extends StatelessWidget {
  const WebSidebar({super.key, required this.session, required this.role, required this.items, required this.current,
      required this.onSelect});
  final Session session;
  final String role;
  final List<WebNavItem> items;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final u = session.user ?? const {};
    final name = '${u['full_name'] ?? ''}';
    final navWidgets = <Widget>[];
    for (final (i, it) in items.indexed) {
      if (i == 0 || items[i - 1].group != it.group) {
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
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Điểm danh', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
              Text(role, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
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
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
                Text('${u['username'] ?? ''}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
            ),
            // Gộp vào một menu để tên người dùng đủ chỗ.
            PopupMenuButton<String>(
              tooltip: 'Tài khoản',
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.more_vert, size: 19, color: AppColors.textSecondary),
              onSelected: (v) => v == 'password' ? ChangePasswordPage.open(context, session) : session.logout(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'password', child: ListTile(dense: true, leading: Icon(Icons.lock_reset, size: 19),
                    title: Text('Đổi mật khẩu'))),
                PopupMenuItem(value: 'logout', child: ListTile(dense: true, leading: Icon(Icons.logout, size: 19),
                    title: Text('Đăng xuất'))),
              ],
            ),
          ]),
        ),
      ]),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.active, required this.onTap});
  final WebNavItem item;
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
                Expanded(
                  child: Text(item.label,
                      style: TextStyle(fontSize: 14, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: color)),
                ),
                if ((item.badge ?? 0) > 0)
                  Pill('${item.badge}', bg: const Color(0xFFFFFBEB), fg: const Color(0xFFB45309), border: const Color(0xFFFDE68A),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Đầu trang mờ kính có breadcrumb "Nhóm / Trang", cùng cột với nội dung trang.
class WebTopBar extends StatelessWidget {
  const WebTopBar({super.key, required this.group, required this.title, required this.showMenu, this.action});
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
          decoration: const BoxDecoration(
            color: Color(0xD9F6F8FC),
            border: Border(bottom: BorderSide(color: Color(0x99E2E8F0))),
          ),
          // Cùng cột với nội dung trang (tối đa webContentMaxWidth, lề 32) để đường dẫn thẳng hàng với tiêu đề.
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: webContentMaxWidth + 64),
            child: Padding(
              padding: EdgeInsets.fromLTRB(showMenu ? 8 : 32, 10, 32, 10),
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
        ),
      ),
    );
  }
}
