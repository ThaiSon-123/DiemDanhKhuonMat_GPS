import 'package:go_router/go_router.dart';

import 'core/session.dart';
import 'features/auth/change_password_page.dart';
import 'features/auth/login_page.dart';
import 'features/admin/admin_shell.dart';
import 'features/lecturer/lecturer_home_page.dart';
import 'features/lecturer/lecturer_nav.dart';
import 'features/student/consent_page.dart';
import 'features/student/enroll_page.dart';
import 'features/student/my_face_page.dart';
import 'features/student/student_home_page.dart';

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
        GoRoute(path: '/student', builder: (_, _) => StudentHomePage(session: session), routes: [
          GoRoute(path: 'consent', builder: (_, _) => ConsentPage(session: session)),
          GoRoute(path: 'enroll', builder: (_, _) => EnrollPage(session: session)),
          GoRoute(path: 'face', builder: (_, _) => MyFacePage(session: session)),
        ]),
        GoRoute(path: '/lecturer', builder: (_, _) => LecturerHomePage(session: session), routes: [
          GoRoute(path: 'faces', builder: (_, _) => LecturerFacesPage(session: session)),
        ]),
        GoRoute(path: '/admin', builder: (_, _) => AdminShell(session: session)),
      ],
    );
