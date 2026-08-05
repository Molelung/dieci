import 'package:flutter/material.dart';

/// 统一的 AI 错误提示：识别 Key/授权类错误时附带「去设置」快捷入口
void showAiError(
  BuildContext context,
  String error, {
  VoidCallback? onSettings,
}) {
  final isKey =
      error.contains('API Key') || error.contains('401') || error.contains('Key');
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(error, maxLines: 3, overflow: TextOverflow.ellipsis),
        duration: const Duration(seconds: 6),
        action: isKey
            ? SnackBarAction(
                label: '去设置',
                onPressed: onSettings ?? () {},
              )
            : null,
      ),
    );
}
