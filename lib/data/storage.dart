import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class Storage {
  Storage._();

  static Directory? _dir;

  static Future<Directory> dir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    _dir = Directory('${base.path}${Platform.pathSeparator}dieci_data');
    await _dir!.create(recursive: true);
    return _dir!;
  }

  static Future<File> notebooksFile() async {
    final d = await dir();
    return File('${d.path}${Platform.pathSeparator}notebooks.json');
  }

  /// 原子写入：同目录 tmp + flush → 旧文件留底 .bak → rename 生效。
  /// 任何一步失败都不会让主文件处于「写了一半」状态。
  static Future<void> writeAtomic(File file, String content) async {
    final tmp = File('${file.path}.tmp');
    final raf = await tmp.open(mode: FileMode.write);
    try {
      await raf.writeString(content);
      await raf.flush();
    } finally {
      await raf.close();
    }

    if (file.existsSync()) {
      final bak = File('${file.path}.bak');
      try {
        if (bak.existsSync()) bak.deleteSync();
        await file.rename(bak.path);
      } catch (_) {
        // 备份失败不阻断主流程
      }
    }

    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
    try {
      await tmp.rename(file.path);
    } catch (_) {
      await tmp.copy(file.path);
    }
  }

  /// 带恢复的读取：主文件 → .bak → .tmp，均需合法 JSON；
  /// 全部损坏时把主文件改名留底（.corrupt-<ts>），不静默覆盖历史。
  static Future<String?> readWithRecovery(File file) async {
    for (final candidate in [
      file,
      File('${file.path}.bak'),
      File('${file.path}.tmp'),
    ]) {
      if (!candidate.existsSync()) continue;
      try {
        final content = await candidate.readAsString();
        if (content.trim().isEmpty) continue;
        jsonDecode(content);
        return content;
      } catch (_) {
        // 读取/解析失败，尝试下一份
      }
    }

    if (file.existsSync()) {
      try {
        final corrupt = File(
            '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
        await file.rename(corrupt.path);
      } catch (_) {}
    }
    return null;
  }
}
