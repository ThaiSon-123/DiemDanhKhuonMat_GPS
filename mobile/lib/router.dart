import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'core/session.dart';
import 'features/auth/change_password_page.dart';
import 'features/auth/login_page.dart';
import 'features/admin/admin_shell.dart';
import 'features/lecturer/lecturer_home_page.dart';
import 'features/lecturer/lecturer_nav.dart';
import 'features/lecturer/lecturer_shell.dart';
import 'features/lecturer/live_session_page.dart';
import 'features/lecturer/open_session_page.dart';
import 'features/lecturer/report_page.dart';
import 'features/lecturer/room_code_page.dart';
import 'features/lecturer/session_history_page.dart';
import 'features/lecturer/student_detail_page.dart';
import 'features/student/checkin/checkin_page.dart';
import 'features/student/consent_page.dart';
import 'features/student/enroll_page.dart';
import 'features/student/history_page.dart';
import 'features/student/my_face_page.dart';
import 'features/student/student_home_page.dart';

final _rootKey = GlobalKey<NavigatorState>();

int _id(GoRouterState st, String k) => int.parse(st.pathParameters[k]!);

const homeByRole = {'student': '/student', 'lecturer': '/lecturer', 'admin': '/admin'};

GoRouter buildRouter(Session session) => GoRouter(
      navigatorKey: _rootKey,
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
          GoRoute(path: 'history', builder: (_, _) => StudentHistoryPage(session: session)),
          GoRoute(
              path: 'checkin/:sid',
              builder: (_, st) => CheckinPage(
                    session: session,
                    sessionId: int.parse(st.pathParameters['sid']!),
                    classCode: st.uri.queryParameters['code'] ?? '',
                    className: st.uri.queryParameters['name'] ?? '',
                  )),
        ]),
        ShellRoute(
          builder: (_, st, child) => LecturerShell(session: session, location: st.uri.path, child: child),
          routes: [
        GoRoute(path: '/lecturer', builder: (_, _) => LecturerHomePage(session: session), routes: [
          GoRoute(path: 'faces', builder: (_, _) => LecturerFacesPage(session: session)),
          GoRoute(path: 'project', builder: (_, _) => ProjectPickerPage(session: session)),
          GoRoute(path: 'report', builder: (_, _) => ReportPage(session: session, standalone: true)),
          GoRoute(
              path: 'open/:cid',
              builder: (_, st) => OpenSessionPage(session: session, classId: _id(st, 'cid'),
                  classCode: st.uri.queryParameters['code'] ?? '', studentCount: int.tryParse(st.uri.queryParameters['n'] ?? ''))),
          GoRoute(
              path: 'history/:cid',
              builder: (_, st) => SessionHistoryPage(session: session, classId: _id(st, 'cid'),
                  classCode: st.uri.queryParameters['code'] ?? '', studentCount: int.tryParse(st.uri.queryParameters['n'] ?? ''))),
          GoRoute(path: 'report/:cid', builder: (_, st) => ReportPage(session: session, classId: _id(st, 'cid'), standalone: true)),
          GoRoute(path: 'session/:sid', builder: (_, st) => LiveSessionPage(session: session, sessionId: _id(st, 'sid')), routes: [
            // Màn chiếu toàn màn hình: nằm trên navigator gốc, không có thanh bên.
            GoRoute(
                path: 'room',
                parentNavigatorKey: _rootKey,
                builder: (_, st) => RoomCodePage(session: session, sessionId: _id(st, 'sid'))),
            GoRoute(
                path: 'student/:uid',
                builder: (_, st) => StudentDetailPage(session: session, sessionId: _id(st, 'sid'), studentId: _id(st, 'uid'))),
          ]),
        ]),
          ],
        ),
        GoRoute(path: '/admin', builder: (_, _) => AdminShell(session: session)),
      ],
    );
