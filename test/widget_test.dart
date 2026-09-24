import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:moon_app/main.dart';

void main() {
  testWidgets('App boots to gate', (WidgetTester tester) async {
    await tester.pumpWidget(const MoonApp());
    // 启动门显示加载指示
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
