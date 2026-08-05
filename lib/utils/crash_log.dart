import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 错误日志落盘：单文件 ≤ 1MB，超出轮转为 .1 / .2，保留 3 份
class CrashLog {
  CrashLog._();

  static File? _file;
  static bool _busy = false;

  static Future<File> _ensure() async {
    if (_file != null) return _file!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}dieci_logs');
    await dir.create(recursive: true);
    _file = File('${dir.path}${Platform.pathSeparator}error.log');
    return _file!;
  }

  static void log(String message) {
    unawaited(_append('${DateTime.now().toIso8601String()}\n$message\n'));
  }

  static Future<void> _append(String entry) async {
    if (_busy) return;
    _busy = true;
    try {
      final file = await _ensure();
      if (file.existsSync() && file.lengthSync() > 1024 * 1024) {
        final f1 = File('${file.path}.1');
        final f2 = File('${file.path}.2');
        try {
          if (f2.existsSync()) f2.deleteSync();
          if (f1.existsSync()) await f1.rename(f2.path);
          await file.rename(f1.path);
        } catch (_) {}
      }
      final raf = await file.open(mode: FileMode.append);
      try {
        await raf.writeString(entry);
        await raf.flush();
      } finally {
        await raf.close();
      }
    } catch (_) {
      // 日志失败不影响主流程
    } finally {
      _busy = false;
    }
  }
}
