import 'package:diemdanh/core/session.dart';
import 'package:diemdanh/main.dart';
import 'package:diemdanh/features/auth/change_password_page.dart';
import 'package:diemdanh/router.dart';
import 'package:diemdanh/ui/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_http.dart';

Map<String, Object> loginOk(String role, {bool mustChange = false}) => {
      'access_token': 'a',
      'refresh_token': 'r',
      'expires_in': 900,
      'user': {'id': 1, 'role': role, 'full_name': 'Nguyễn Văn An', 'must_change_password': mustChange},
    };

Finder field(String label) =>
    find.descendant(of: find.widgetWithText(AppTextField, label), matching: find.byType(TextField));

Future<void> login(WidgetTester t, Reply reply) async {
  // Khổ điện thoại như artboard (390×844); màn test mặc định 800×600 đẩy nút ra ngoài.
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final session = Session(fakeClient(FakeHttp((_) => reply)));
  await t.pumpWidget(DiemDanhApp(router: buildRouter(session)));
  await t.enterText(field('Email trường'), 'sv001@truong.edu.vn');
  await t.enterText(field('Mật khẩu'), 'sai-mat-khau');
  await t.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('sai mật khẩu: hiện thông điệp từ server', (t) async {
    await login(t, (401, apiErr('AUTH_INVALID_CREDENTIALS', 'Email hoặc mật khẩu không đúng')));
    expect(find.text('Email hoặc mật khẩu không đúng'), findsOneWidget);
  });

  testWidgets('must_change_password: chuyển sang trang đổi mật khẩu', (t) async {
    await login(t, (200, loginOk('student', mustChange: true)));
    expect(find.text('Đặt mật khẩu mới'), findsOneWidget);
  });

  testWidgets('đăng nhập giảng viên: vào trang chủ giảng viên, đăng xuất về trang đăng nhập', (t) async {
    await login(t, (200, loginOk('lecturer')));
    expect(find.textContaining('Giảng viên'), findsWidgets);
    await t.tap(find.byTooltip('Đăng xuất'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Đăng nhập'), findsOneWidget);
  });

  testWidgets('đổi mật khẩu: báo chưa khớp ngay dưới ô nhập lại', (t) async {
    await login(t, (200, loginOk('student', mustChange: true)));
    await t.enterText(field('Mật khẩu tạm'), 'Tmp-4821');
    await t.enterText(field('Mật khẩu mới'), 'matkhaumoi2026');
    await t.enterText(field('Nhập lại mật khẩu mới'), 'matkhaumoi202');
    await t.pump();
    expect(find.text('Hai mật khẩu chưa khớp'), findsOneWidget);
  });

  test('độ mạnh mật khẩu', () {
    expect(passwordStrength(''), 0);
    expect(passwordStrength('abcdefgh'), 1);
    expect(passwordStrength('matkhaumoi2026'), 3);
    expect(passwordStrength('MatKhauMoi2026'), 4);
  });
}
