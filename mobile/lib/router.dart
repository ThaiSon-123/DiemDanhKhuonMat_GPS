import 'package:go_router/go_router.dart';

import 'core/session.dart';
import 'features/auth/change_password_page.dart';
import 'features/auth/login_page.dart';
import 'features/home/role_home_page.dart';

const homeByRole = {'student': '/student', 'lecturer': '/lecturer', 'admin': '/admin'};

GoRouter buildRouter(Session session) => GoRouter(
      initialLocation: '/login',
      refreshListenable: session,
      redirect: (_, state) {
        final at = state.matchedLocation;
        if (!session.loggedIn) return at == '/login' ? null : '/login';
        if (session.mustChangePassword) return at == '/change-password' ? null : '/change-password';
        final home = homeByRole[session.role] ?? '/login';
        return at.startsWith(home) ? null : home;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, _) => LoginPage(session: session)),
        GoRoute(path: '/change-password', builder: (_, _) => ChangePasswordPage(session: session)),
        for (final e in {'student': 'Sinh viên', 'lecturer': 'Giảng viên', 'admin': 'Quản trị viên'}.entries)
          GoRoute(path: homeByRole[e.key]!, builder: (_, _) => RoleHomePage(session: session, roleName: e.value)),
      ],
    );
