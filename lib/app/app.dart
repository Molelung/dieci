import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../features/home/notebooks_page.dart';

class DieciApp extends StatelessWidget {
  const DieciApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '叠词',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const NotebooksPage(),
    );
  }
}
