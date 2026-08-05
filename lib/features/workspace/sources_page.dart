import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/glass_input.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../utils/obsidian_importer.dart';

class SourcesPage extends StatefulWidget {
  final String notebookId;

  const SourcesPage({super.key, required this.notebookId});

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  bool _importing = false;

  Future<void> _pasteText() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        content: GlassCard(
          radius: 24,
          blur: 30,
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('粘贴学习材料',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Tokens.textPrimary)),
                const SizedBox(height: 6),
                const Text('可以是笔记、讲义、文章，AI 会按段落自动切分',
                    style: TextStyle(
                        fontSize: 12, color: Tokens.textTertiary)),
                const SizedBox(height: 14),
                GlassInput(
                  controller: controller,
                  hint: '粘贴 Markdown / 纯文本…',
                  maxLines: 10,
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GlassButton(
                      label: '取消',
                      style: GlassButtonStyle.ghost,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                    const SizedBox(width: 10),
                    GlassButton(
                      label: '导入',
                      icon: Icons.add_rounded,
                      onPressed: () {
                        final t = controller.text.trim();
                        if (t.isEmpty) return;
                        Navigator.pop(ctx, t);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (text != null && text.isNotEmpty && mounted) {
      _addSource('粘贴的笔记', text, 'text');
    }
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown', 'txt'],
      );
      if (result == null || !mounted) return;
      var count = 0;
      for (final f in result.files) {
        if (f.path == null) continue;
        final file = File(f.path!);
        if (!file.existsSync()) continue;
        final content = await file.readAsString();
        if (content.trim().isEmpty) continue;
        _addSource(f.name, ObsidianImporter.stripFrontmatter(content), 'file',
            filePath: f.path);
        count++;
      }
      if (count == 0) _toast('没有可导入的 .md 文件');
    } catch (e) {
      _toast('导入失败：$e');
    }
  }

  Future<void> _pickVault() async {
    String? dir;
    try {
      dir = await FilePicker.platform.getDirectoryPath();
    } catch (e) {
      _toast('无法选择目录（桌面端体验最佳）：$e');
      return;
    }
    if (dir == null || !mounted) return;

    setState(() => _importing = true);
    try {
      final result = await ObsidianImporter.scanVault(dir);
      if (result.files.isEmpty) {
        _toast('该目录下没有找到 .md 笔记');
        return;
      }
      var added = 0;
      for (final f in result.files) {
        final body = ObsidianImporter.stripFrontmatter(f.content);
        if (body.trim().isEmpty) continue;
        _addSource(f.name, body, 'obsidian', filePath: f.path);
        added++;
      }
      _toast('已导入 Obsidian 库：$added 篇笔记（跳过 ${result.skipped} 个文件）');
    } catch (e) {
      _toast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _addSource(String name, String text, String type, {String? filePath}) {
    final nb = Repo.i.notebook(widget.notebookId);
    Repo.i.addSource(
      nb,
      name: name,
      text: text,
      type: type,
      filePath: filePath,
    );
    _toast('已导入「$name」');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Repo.i,
      builder: (context, _) {
        final nb = Repo.i.notebook(widget.notebookId);
        if (nb.sources.isEmpty) return _empty();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  GlassButton(
                    label: _importing ? '导入中…' : '导入 Obsidian 笔记库',
                    icon: Icons.folder_open_rounded,
                    style: GlassButtonStyle.outline,
                    loading: _importing,
                    onPressed: _importing ? null : _pickVault,
                  ),
                  GlassButton(
                    label: '导入 .md 文件',
                    icon: Icons.upload_file_rounded,
                    style: GlassButtonStyle.outline,
                    onPressed: _pickFiles,
                  ),
                  GlassButton(
                    label: '粘贴文本',
                    icon: Icons.content_paste_rounded,
                    style: GlassButtonStyle.ghost,
                    onPressed: _pasteText,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                itemCount: nb.sources.length,
                itemBuilder: (context, i) {
                  final s = nb.sources[i];
                  return _sourceCard(nb, s);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _empty() {
    return Center(
      child: GlassCard(
        glow: true,
        margin: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_copy_rounded,
                  size: 46, color: Tokens.brandViolet),
              const SizedBox(height: 14),
              const Text('还没有学习材料',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Tokens.textPrimary)),
              const SizedBox(height: 8),
              const Text(
                '导入你的 Obsidian 笔记库（只读，不会改动你的笔记），\n或粘贴文本。之后 AI 就能围绕你的学习主题\n生成大纲并出题复习。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, height: 1.7, color: Tokens.textSecondary),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  GlassButton(
                    label: _importing ? '导入中…' : '选择 Obsidian 库文件夹',
                    icon: Icons.folder_open_rounded,
                    loading: _importing,
                    onPressed: _importing ? null : _pickVault,
                  ),
                  GlassButton(
                    label: '粘贴文本',
                    icon: Icons.content_paste_rounded,
                    style: GlassButtonStyle.outline,
                    onPressed: _pasteText,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceCard(Notebook nb, Source s) {
    final typeLabel = switch (s.type) {
      'obsidian' => 'Obsidian',
      'file' => '文件',
      'chat' => '对话沉淀',
      _ => '文本',
    };
    final icon = switch (s.type) {
      'obsidian' => Icons.workspaces_rounded,
      'file' => Icons.description_rounded,
      'chat' => Icons.chat_rounded,
      _ => Icons.article_rounded,
    };
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => _showDetail(s),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: notebookGradient(
                  nb.gradientIndex + s.id.hashCode % 3),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Tokens.textPrimary)),
                const SizedBox(height: 3),
                Text(
                  '${s.rawText.length} 字符 · ${s.chunks?.length ?? 0} 分块 · $typeLabel',
                  style: const TextStyle(
                      fontSize: 11, color: Tokens.textTertiary),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Repo.i.removeSource(nb, s.id),
            child: Icon(Icons.delete_outline_rounded,
                size: 18,
                color: Tokens.textTertiary.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  void _showDetail(Source s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        content: GlassCard(
          radius: 24,
          blur: 30,
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 560,
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Tokens.textPrimary)),
                const SizedBox(height: 6),
                if (s.filePath != null)
                  Text(s.filePath!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: Tokens.textTertiary)),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        s.rawText,
                        style: const TextStyle(
                            fontSize: 13, height: 1.6, color: Tokens.textSecondary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: GlassButton(
                    label: '复制全文',
                    icon: Icons.copy_rounded,
                    style: GlassButtonStyle.outline,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: s.rawText));
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
