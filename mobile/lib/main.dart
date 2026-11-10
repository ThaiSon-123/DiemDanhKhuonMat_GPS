import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/api_client.dart';
import 'core/session.dart';
import 'core/token_store.dart';
import 'router.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = Session(ApiClient(SecureTokenStore()));
  await session.restore();
  runApp(DiemDanhApp(router: buildRouter(session)));
}

class DiemDanhApp extends StatelessWidget {
  const DiemDanhApp({super.key, required this.router});
  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Điểm danh',
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        routerConfig: router,
      );
}
