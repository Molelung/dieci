import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/widgets/gradient_background.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../settings/settings_page.dart';
import '../workspace/workspace_page.dart';

class NotebooksPage extends StatelessWidget {
  const NotebooksPage({super.key});

  Future<void> _createNotebook(BuildContext context) async {
    final nameController = TextEditingController();
    var gradientIndex = 0;

    final created = await showDialog<Notebook>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: Colors.transparent,
          content: GlassCard(
            radius: 24,
            blur: 30,
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('新建笔记本',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Tokens.textPrimary)),
                  const SizedBox(height: 16),
                  GlassInput(
                    controller: nameController,
                    label: '名称',
                    hint: '例如：考研高数 / 计算机网络 / 法语',
                  ),
                  const SizedBox(height: 16),
                  const Text('封面',
                      style: TextStyle(
                          fontSize: 13, color: Tokens.textSecondary)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: notebookGradients.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (ctx, i) => GestureDetector(
                        onTap: () => setState(() => gradientIndex = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 40,
                          decoration: BoxDecoration(
                            gradient: notebookGradient(i),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: gradientIndex == i
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
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
                        label: '创建',
                        icon: Icons.add_rounded,
                        onPressed: () {
                          final name = nameController.text.trim();
                          if (name.isEmpty) return;
                          Navigator.pop(
                              ctx, Repo.i.createNotebook(name, gradientIndex));
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (created != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WorkspacePage(notebookId: created.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Repo.i,
            builder: (context, _) {
              final notebooks = Repo.i.notebooks;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 20, 20, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: Tokens.brandGradient,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Tokens.brandPink.withValues(alpha: 0.4),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.auto_stories_rounded,
                              color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 14),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('叠词',
                                style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: Tokens.textPrimary,
                                    letterSpacing: 2)),
                            Text('轻盈 · 高效 · 碎片化复习',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Tokens.textTertiary)),
                          ],
                        ),
                        const Spacer(),
                        GlassButton(
                          label: '设置',
                          icon: Icons.settings_rounded,
                          style: GlassButtonStyle.outline,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SettingsPage()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: notebooks.isEmpty
                        ? _emptyState(context)
                        : _grid(context, notebooks),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createNotebook(context),
        backgroundColor: Tokens.brandPink,
        foregroundColor: Colors.white,
        elevation: 8,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建笔记本',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: GlassCard(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        glow: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 48, color: Tokens.brandBlue),
              const SizedBox(height: 16),
              const Text('开始你的高效复习',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Tokens.textPrimary)),
              const SizedBox(height: 10),
              const Text(
                '导入 Obsidian 笔记库或粘贴学习材料，\n输入一个学习主题，叠词会自动生成大纲并出题，\n只复习与你主题相关的内容。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.7,
                    color: Tokens.textSecondary),
              ),
              const SizedBox(height: 20),
              GlassButton(
                label: '创建第一个笔记本',
                icon: Icons.rocket_launch_rounded,
                onPressed: () => _createNotebook(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, List notebooks) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.92,
      ),
      itemCount: notebooks.length,
      itemBuilder: (context, i) {
        final nb = notebooks[i] as dynamic;
        return GlassCard(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => WorkspacePage(notebookId: nb.id as String)),
          ),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 74,
                decoration: BoxDecoration(
                  gradient: notebookGradient(nb.gradientIndex as int),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(Tokens.radiusLg - 1)),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -12,
                      bottom: -16,
                      child: Icon(Icons.auto_awesome_rounded,
                          size: 64,
                          color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    Positioned(
                      left: 14,
                      bottom: 10,
                      child: Text(
                        nb.name as String,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(
                  children: [
                    _stat('${(nb.sources as List).length}', '来源'),
                    const SizedBox(width: 14),
                    _stat('${(nb.questions as List).length}', '题目'),
                    const SizedBox(width: 14),
                    _stat('${(nb.mistakes as List).length}', '错题'),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Repo.i.deleteNotebook(nb.id as String),
                      child: Icon(Icons.delete_outline_rounded,
                          size: 18, color: Tokens.textTertiary.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Tokens.textPrimary)),
        Text(label,
            style:
                const TextStyle(fontSize: 11, color: Tokens.textTertiary)),
      ],
    );
  }
}
