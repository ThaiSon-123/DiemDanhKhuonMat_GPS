import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';

/// Tạm thời cho tab "Tài khoản" cho đến khi có màn tài khoản thật: thông tin + đăng xuất.
Future<void> showAccountSheet(BuildContext context, Session session) {
  final u = session.user ?? const {};
  final name = '${u['full_name'] ?? ''}';
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            InitialsAvatar(name, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
                Text('${u['username'] ?? ''}', style: mono.copyWith(fontSize: 13, color: AppColors.textMuted)),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.absentSoft,
              foregroundColor: AppColors.absentText,
              elevation: 0,
              side: const BorderSide(color: AppColors.absentBorder),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              session.logout();
            },
            icon: const Icon(Icons.logout, size: 19),
            label: const Text('Đăng xuất'),
          ),
        ]),
      ),
    ),
  );
}
