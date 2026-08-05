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

  test('设计令牌：品牌渐变存在且终端值正确', () {
    expect(Tokens.brandPink, const Color(0xFFFB7299));
    expect(Tokens.brandBlue, const Color(0xFF00AEEC));
    expect(notebookGradients.length, greaterThanOrEqualTo(4));
  });
}
