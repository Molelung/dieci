import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../ai/gemini_client.dart';
import '../../ai/prompts.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/error_toast.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/widgets/hero_art.dart';
import '../../data/chunker.dart';
import '../../data/repository.dart';
import '../../data/settings_store.dart';
import '../../models/models.dart';
import '../../features/settings/settings_page.dart';
import 'practice_page.dart';

class OutlinePage extends StatefulWidget {
  final String notebookId;

  const OutlinePage({super.key, required this.notebookId});

  @override
  State<OutlinePage> createState() => _OutlinePageState();
}

class _OutlinePageState extends State<OutlinePage> {
  final _topicController = TextEditingController();
  final _selected = <String>{};
  final _collapsed = <String>{};
  CancelToken? _cancel;
  StreamSubscription<String>? _sub;
  bool _generating = false;
  String _status = '';

  @override
  void dispose() {
    _sub?.cancel();
    _cancel?.cancel();
    _topicController.dispose();
    super.dispose();
  }

  List<Chunk> _gatherChunks(Notebook nb, String topic) {
    final all = nb.sources
        .expand((s) => s.chunks ?? <Chunk>[])
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return Chunker.selectRelevant(all, topic, maxChars: 12000);
  }

  Future<void> _generate() async {
    final nb = Repo.i.notebook(widget.notebookId);
    final topic = _topicController.text.trim();

    if (nb.sources.isEmpty) {
      _toast('请先到「来源」导入学习材料（支持 Obsidian 笔记库）');
      return;
    }

    final chunks = _gatherChunks(nb, topic);
    if (chunks.isEmpty) {
      _toast('没有与主题相关的内容，换个主题词试试');
      return;
    }

    final material = chunks.map((c) => '[${c.index}] ${c.text}').join('\n\n');
    final client = GeminiClient(SettingsStore.i);

    setState(() {
      _generating = true;
      _status = 'AI 正在生成大纲…（边生成边渲染）';
      nb.outline.clear();
      _selected.clear();
    });
    Repo.i.save();

    final buf = StringBuffer();
    var lastCount = 0;
    _cancel = CancelToken();
    try {
      _sub = client
          .streamGenerate(
            contents: [AiMessage('user', Prompts.outlineUser(topic, material))],
            system: Prompts.outlineSystem(),
            temperature: 0.4,
            maxTokens: 4096,
            cancelToken: _cancel,
          )
          .listen(
        (delta) {
          if (!mounted) return;
          buf.write(delta);
          final nodes = _parseOutline(buf.toString());
          final count = _countNodes(nodes);
          if (count == lastCount) return; // 渲染节流：无新节点不重建
          lastCount = count;
          setState(() {
            nb.outline
              ..clear()
              ..addAll(nodes);
          });
        },
        onError: (Object e) {
          if (!mounted) return;
          setState(() {
            _generating = false;
            _status = '生成失败：$e';
          });
          Repo.i.save();
          showAiError(
            context,
            '$e',
            onSettings: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          );
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _generating = false;
            if (nb.outline.isEmpty) {
              _status = '未解析到大纲，请重试';
            } else {
              _status = '大纲生成完成（${_countNodes(nb.outline)} 个节点）';
            }
          });
          Repo.i.save();
        },
      );
      await _sub!.asFuture();
    } catch (e) {
      if (mounted) setState(() => _status = '生成失败：$e');
    } finally {
      if (mounted && _generating) setState(() => _generating = false);
      Repo.i.save();
    }
  }

  void _stop() {
    _sub?.cancel();
    setState(() {
      _generating = false;
      _status = '已停止，当前大纲已保留';
    });
  }

  static int _countNodes(List<OutlineNode> nodes) =>
      nodes.fold(0, (sum, n) => sum + 1 + _countNodes(n.children));

  static List<OutlineNode> _parseOutline(String text) {
    final roots = <OutlineNode>[];
    final stack = <OutlineNode>[];
    var idc = 0;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      final m = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(line);
      if (m == null) continue;
      final depth = m.group(1)!.length;
      final node = OutlineNode(
        id: 'on-${widgetKey++}-$idc',
        title: m.group(2)!.trim(),
        depth: depth,
      );
      idc++;
      while (stack.isNotEmpty && stack.last.depth >= depth) {
        stack.removeLast();
      }
      if (stack.isEmpty) {
        roots.add(node);
      } else {
        stack.last.children.add(node);
      }
      stack.add(node);
    }
    return roots;
  }

  static int widgetKey = 0;

  Future<void> _startPractice(Notebook nb) async {
    if (_selected.isEmpty) {
      _toast('请先勾选要复习的大纲节点');
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PracticePage(
          notebookId: widget.notebookId,
          presetScope: _selected.toList(),
        ),
      ),
    );
  }

  static Set<String> _allNodeIds(List<OutlineNode> nodes) {
    final ids = <String>{};
    for (final n in nodes) {
      ids.add(n.id);
      ids.addAll(_allNodeIds(n.children));
    }
    return ids;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Repo.i,
      builder: (context, _) {
        final nb = Repo.i.notebook(widget.notebookId);
        final hasOutline = nb.outline.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: GlassInput(
                      controller: _topicController,
                      hint: '输入学习主题，例如「神经网络」',
                      icon: Icons.flag_rounded,
                    ),
                  ),
                  GlassButton(
                    label: _generating ? '生成中…' : '生成大纲',
                    icon: Icons.account_tree_rounded,
                    loading: _generating,
                    onPressed: _generating ? null : _generate,
                  ),
                  if (_generating)
                    GlassButton(
                      label: '停止',
                      style: GlassButtonStyle.ghost,
                      onPressed: _stop,
                    ),
                  if (hasOutline && !_generating)
                    GlassButton(
                      label: '对勾选范围出题（${_selected.length}）',
                      icon: Icons.quiz_rounded,
                      style: GlassButtonStyle.outline,
                      onPressed: () => _startPractice(nb),
                    ),
                  if (hasOutline && !_generating) ...[
                    GlassButton(
                      label: '全选',
                      style: GlassButtonStyle.ghost,
                      onPressed: () => setState(() {
                        _selected.clear();
                        _selected.addAll(_allNodeIds(nb.outline));
                      }),
                    ),
                    GlassButton(
                      label: '清空',
                      style: GlassButtonStyle.ghost,
                      onPressed: () => setState(_selected.clear),
                    ),
                  ],
                ],
              ),
            ),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Text(_status,
                    style: const TextStyle(
                        fontSize: 12, color: Tokens.textTertiary)),
              ),
            Expanded(
              child: hasOutline
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        for (final node in nb.outline)
                          _OutlineNodeTile(
                            node: node,
                            selected: _selected,
                            collapsed: _collapsed,
                            level: 0,
                            onToggle: () => setState(() {}),
                          ),
                      ],
                    )
                  : _empty(nb),
            ),
          ],
        );
      },
    );
  }

  Widget _empty(Notebook nb) {
    final hasSources = nb.sources.isNotEmpty;
    return Center(
      child: GlassCard(
        glow: true,
        margin: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HeroArt(
                icon: hasSources
                    ? Icons.account_tree_rounded
                    : Icons.library_add_rounded,
              ),
              const SizedBox(height: 18),
              Text(
                hasSources ? '输入主题，生成你的学习大纲' : '先导入学习材料',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Tokens.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                hasSources
                    ? 'AI 会只从材料中提取与主题相关的内容，\n大纲边生成边实时渲染，生成后勾选节点即可出题。'
                    : '去「来源」页导入 Obsidian 笔记库或粘贴笔记，\nAI 才能围绕你的主题生成大纲。',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, height: 1.7, color: Tokens.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlineNodeTile extends StatelessWidget {
  final OutlineNode node;
  final Set<String> selected;
  final Set<String> collapsed;
  final int level;
  final VoidCallback onToggle;

  const _OutlineNodeTile({
    required this.node,
    required this.selected,
    required this.collapsed,
    required this.level,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isSel = selected.contains(node.id);
    final isCollapsed = collapsed.contains(node.id);
    final hasChildren = node.children.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            if (isSel) {
              selected.remove(node.id);
            } else {
              selected.add(node.id);
            }
            onToggle();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: EdgeInsets.only(left: level * 22.0, top: 4, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: isSel
                  ? Tokens.brandBlue.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.7),
              border: Border.all(
                color: isSel
                    ? Tokens.brandBlue.withValues(alpha: 0.5)
                    : Tokens.brandBlue.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isSel
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: isSel ? Tokens.brandBlue : Tokens.textTertiary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    node.title,
                    style: TextStyle(
                      fontSize: node.depth == 1 ? 14.5 : 13,
                      fontWeight:
                          node.depth == 1 ? FontWeight.w700 : FontWeight.w500,
                      color: Tokens.textPrimary,
                    ),
                  ),
                ),
                if (hasChildren)
                  GestureDetector(
                    onTap: () {
                      if (isCollapsed) {
                        collapsed.remove(node.id);
                      } else {
                        collapsed.add(node.id);
                      }
                      onToggle();
                    },
                    child: Icon(
                      isCollapsed
                          ? Icons.chevron_right_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: Tokens.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!isCollapsed)
          for (final child in node.children)
            _OutlineNodeTile(
              node: child,
              selected: selected,
              collapsed: collapsed,
              level: level + 1,
              onToggle: onToggle,
            ),
      ],
    );
  }
}
