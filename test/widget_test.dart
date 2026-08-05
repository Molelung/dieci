import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dieci/app/app.dart';
import 'package:dieci/core/theme/tokens.dart';

void main() {
  testWidgets('叠词 启动冒烟测试', (WidgetTester tester) async {
    await tester.pumpWidget(const DieciApp());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('叠词'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.textContaining('开始你的高效复习'), findsOneWidget);
  });

  test('设计令牌：蓝白主题存在且终端值正确', () {
    expect(Tokens.brandBlue, const Color(0xFF2E7CF6));
    expect(Tokens.brandSky, const Color(0xFF5AC8FA));
    expect(Tokens.bg, const Color(0xFFF3F8FF));
    expect(notebookGradients.length, greaterThanOrEqualTo(4));
  });
}
