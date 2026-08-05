import 'dart:io';

/// Obsidian 笔记库导入结果
class ObsidianFile {
  final String path;
  final String name;
  final String content;

  ObsidianFile({required this.path, required this.name, required this.content});
}

class ObsidianImportResult {
  final String vaultPath;
  final List<ObsidianFile> files;
  final int skipped;

  ObsidianImportResult({
    required this.vaultPath,
    required this.files,
    required this.skipped,
  });
}

class ObsidianImporter {
  ObsidianImporter._();

  /// 递归扫描库目录中的 .md 文件，跳过 .obsidian/.trash/.git 等隐藏目录
  static Future<ObsidianImportResult> scanVault(String vaultPath) async {
    final root = Directory(vaultPath);
    if (!root.existsSync()) {
      throw Exception('目录不存在：$vaultPath');
    }

    final files = <ObsidianFile>[];
    var skipped = 0;

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path;
      final parts = path.replaceAll('\\', '/').split('/');
      final isHiddenDir = parts.any((p) =>
          p.startsWith('.') ||
          p == '.obsidian' ||
          p == '.trash' ||
          p == '.git' ||
          p == 'node_modules');
      if (isHiddenDir) {
        skipped++;
        continue;
      }
      final ext = entity.path.split('.').last.toLowerCase();
      if (ext != 'md' && ext != 'markdown' && ext != 'txt') {
        skipped++;
        continue;
      }
      try {
        final content = await entity.readAsString();
        if (content.trim().isEmpty) {
          skipped++;
          continue;
        }
        files.add(ObsidianFile(
          path: entity.path,
          name: entity.path.split(Platform.pathSeparator).last,
          content: content,
        ));
      } catch (_) {
        skipped++;
      }
    }

    files.sort((a, b) => a.name.compareTo(b.name));
    return ObsidianImportResult(
      vaultPath: vaultPath,
      files: files,
      skipped: skipped,
    );
  }

  /// 剥离 YAML frontmatter，保留正文
  static String stripFrontmatter(String content) {
    final lines = content.split('\n');
    if (lines.isNotEmpty && lines.first.trim() == '---') {
      var end = -1;
      for (var i = 1; i < lines.length; i++) {
        if (lines[i].trim() == '---') {
          end = i;
          break;
        }
      }
      if (end != -1) {
        return lines.sublist(end + 1).join('\n');
      }
    }
    return content;
  }

  /// 提取 [[wikilink]] 目标（v1 仅收集，不建立图）
  static List<String> extractWikilinks(String content) {
    final re = RegExp(r'\[\[([^\[\]|#]+)(?:#[^\[\]|]*)?(?:\|[^\]]*)?\]\]');
    return re
        .allMatches(content)
        .map((m) => m.group(1)!.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }
}
