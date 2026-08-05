import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'app/app.dart';
import 'data/repository.dart';
import 'data/settings_store.dart';
import 'utils/crash_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsStore.i.load();
  await Repo.i.init();

  // 三层错误捕获：框架回调 / 平台异步 / Zone 兜底，统一落盘
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    CrashLog.log('FLUTTER\n${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashLog.log('PLATFORM\n$error\n$stack');
    return true;
  };

  runZonedGuarded(() {
    runApp(const DieciApp());
  }, (error, stack) {
    CrashLog.log('ZONE\n$error\n$stack');
  });
}
