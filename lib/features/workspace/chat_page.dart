import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../ai/gemini_client.dart';
import '../../ai/prompts.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/error_toast.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/hero_art.dart';
import '../../data/chunker.dart';
import '../../data/repository.dart';
import '../../data/settings_store.dart';
import '../../models/models.dart';
import '../../features/settings/settings_page.dart';
import 'practice_page.dart';

class ChatPage extends StatefulWidget {
  final String notebookId;

  const ChatPage({super.key, required this.notebookId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final Map<String, String> _chunkMap = {};
  StreamSubscription<String>? _sub;
  CancelToken? _cancel;
  bool _streaming = false;
  int _usedChunks = 0;

  @override
  void dispose() {
    _sub?.cancel();
    _cancel?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _streaming) return;
    _controller.clear();
    await _sendText(text);
  }

  Future<void> _sendText(String text) async {
    if (text.isEmpty || _streaming) return;
    final nb = Repo.i.notebook(widget.notebookId);
    if (nb.sources.isEmpty) {
      _toast('没有学习材料，请先到「来源」页导入');
      return;
    }
    nb.chatMessages.add(ChatMessage(
      role: 'user',
      text: text,
      createdAt: DateTime.now().toIso8601String(),
    ));

    final chunks = nb.sources
        .expand((s) => s.chunks ?? <Chunk>[])
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final relevant = Chunker.selectRelevant(chunks, text, maxChars: 6000);
    _usedChunks = relevant.length;
    _chunkMap.clear();
    for (final c in relevant) {
      _chunkMap['${c.index}'] = '${c.sourceName ?? '材料'}\n\n${c.text}';
    }
    final material = relevant.map((c) => '[${c.index}] ${c.text}').join('\n\n');

    // 最近对话历史（多轮记忆）：取本次发送之前的最近 6 条，截断超长
    final history = <String>[];
    final prev = nb.chatMessages.take(nb.chatMessages.length - 1).toList();
    final start = prev.length > 6 ? prev.length - 6 : 0;
    for (final m in prev.sublist(start)) {
      final role = m.role == 'user' ? '用户' : '助手';
      final text = m.text.length > 240 ? '${m.text.substring(0, 240)}…' : m.text;
      if (text.trim().isEmpty) continue;
      history.add('$role：$text');
    }

    final modelMsg = ChatMessage(
      role: 'model',
      text: '',
      createdAt: DateTime.now().toIso8601String(),
    );
    nb.chatMessages.add(modelMsg);
    Repo.i.save();
    setState(() => _streaming = true);
    _scrollToBottom();

    final client = GeminiClient(SettingsStore.i);
    final buf = StringBuffer();
    _cancel = CancelToken();
    try {
      _sub = client
          .streamGenerate(
            contents: [AiMessage('user', Prompts.chatUser(material, text, history: history))],
            system: Prompts.chatSystem(),
            temperature: 0.5,
            maxTokens: 2048,
            cancelToken: _cancel,
          )
          .listen(
        (delta) {
          if (!mounted) return;
          buf.write(delta);
          modelMsg.text = buf.toString();
          _scheduleRefresh();
        },
        onError: (Object e) {
          if (!mounted) return;
          modelMsg.text = '⚠️ $e';
          setState(() => _streaming = false);
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
          setState(() => _streaming = false);
          Repo.i.save();
        },
      );
      await _sub!.asFuture();
    } catch (e) {
      if (mounted) {
        modelMsg.text = '⚠️ $e';
        setState(() => _streaming = false);
      }
      Repo.i.save();
    } finally {
      if (mounted && _streaming) setState(() => _streaming = false);
      Repo.i.save();
    }
  }

  bool _dirty = false;

  /// 渲染节流：高频 token 到达合并为一帧一次刷新
  void _scheduleRefresh() {
    if (_dirty) return;
    _dirty = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dirty = false;
      if (!mounted) return;
      setState(() {});
      _scrollToBottom();
    });
  }

  void _stop() {
    _sub?.cancel();
    setState(() => _streaming = false);
  }

  void _sediment(Notebook nb, ChatMessage msg) {
    if (msg.text.trim().isEmpty) {
      _toast('这条回答是空的，无法沉淀');
      return;
    }
    Repo.i.addSource(
      nb,
      name: '对话沉淀 ${msg.createdAt.substring(11, 19)}',
      text: msg.text,
      type: 'chat',
    );
    _toast('已沉淀为来源，可参与大纲生成与出题');
  }
  void _practiceFrom(Notebook nb, ChatMessage msg) {
    final src = Repo.i.addSource(
      nb,
      name: '对话沉淀 ${msg.createdAt.substring(11, 19)}',
      text: msg.text,
      type: 'chat',
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PracticePage(
          notebookId: widget.notebookId,
          presetSourceId: src.id,
        ),
      ),
    );
  }

  /// 重新生成：删除该条及其后的消息，回到对应的用户提问重跑
  void _regenerateAt(int index) {
    if (_streaming) return;
    final nb = Repo.i.notebook(widget.notebookId);
    final msgs = nb.chatMessages;
    var ui = index - 1;
    while (ui >= 0 && msgs[ui].role != 'user') {
      ui--;
    }
    if (ui < 0) return;
    final question = msgs[ui].text;
    msgs.removeRange(ui, msgs.length);
    Repo.i.save();
    setState(() {});
    _sendText(question);
  }

  void _deleteAt(int index) {
    final nb = Repo.i.notebook(widget.notebookId);
    nb.chatMessages.removeAt(index);
    Repo.i.save();
    setState(() {});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        content: GlassCard(
          radius: 24,
          blur: 30,
          padding: const EdgeInsets.all(22),
          child: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('清空当前对话？',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Tokens.textPrimary)),
                const SizedBox(height: 8),
                const Text('仅清空对话记录，来源与题目不受影响。',
                    style: TextStyle(
                        fontSize: 12, color: Tokens.textSecondary)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GlassButton(
                      label: '取消',
                      style: GlassButtonStyle.ghost,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                    const SizedBox(width: 10),
                    GlassButton(
                      label: '清空',
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final nb = Repo.i.notebook(widget.notebookId);
    nb.chatMessages.clear();
    Repo.i.save();
    setState(() {});
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
        if (nb.sources.isEmpty) {
          return Center(
            child: GlassCard(
              margin: const EdgeInsets.all(24),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_rounded,
                      size: 42, color: Tokens.brandCyan),
                  SizedBox(height: 12),
                  Text('先导入学习材料，再向 AI 提问',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Tokens.textPrimary)),
                  SizedBox(height: 6),
                  Text('回答基于你的材料，可一键沉淀为来源',
                      style: TextStyle(
                          fontSize: 12, color: Tokens.textSecondary)),
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            Expanded(
              child: nb.chatMessages.isEmpty
                  ? _welcome()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      itemCount: nb.chatMessages.length,
                      itemBuilder: (context, i) {
                        final m = nb.chatMessages[i];
                        return _bubble(nb, m, index: i);
                      },
                    ),
            ),
            _inputBar(),
          ],
        );
      },
    );
  }

  Widget _welcome() {
    return Center(
      child: GlassCard(
        glow: true,
        margin: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HeroArt(icon: Icons.forum_rounded, size: 84),
              const SizedBox(height: 16),
              const Text('向你的笔记库提问',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Tokens.textPrimary)),
              const SizedBox(height: 8),
              const Text(
                '例如：「梯度消失有哪些解决办法？」\n回答只基于你的笔记材料，并标注出处。\n满意的回答可以一键「沉淀为来源」，继续出题复习。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, height: 1.7, color: Tokens.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(Notebook nb, ChatMessage m, {required int index}) {
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        child: GlassCard(
          radius: 16,
          padding: const EdgeInsets.all(13),
          fill: isUser
              ? Tokens.brandBlue.withValues(alpha: 0.10)
              : Tokens.glassFill,
          borderGradient: isUser
              ? LinearGradient(colors: [
                  Tokens.brandSky.withValues(alpha: 0.6),
                  Tokens.brandBlue.withValues(alpha: 0.4),
                ])
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Row(
                  children: [
                    const Text('AI',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Tokens.brandBlue)),
                    if (_streaming && m.text.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      ),
                    const Spacer(),
                    if (m.text.isNotEmpty && !_streaming)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _miniAction(
                            icon: Icons.folder_rounded,
                            tooltip: '沉淀为来源',
                            onTap: () => _sediment(nb, m),
                          ),
                          const SizedBox(width: 6),
                          _miniAction(
                            icon: Icons.quiz_rounded,
                            tooltip: '据此出题',
                            onTap: () => _practiceFrom(nb, m),
                          ),
                          const SizedBox(width: 6),
                          _miniAction(
                            icon: Icons.refresh_rounded,
                            tooltip: '重新生成',
                            onTap: () => _regenerateAt(index),
                          ),
                          const SizedBox(width: 6),
                          _miniAction(
                            icon: Icons.delete_outline_rounded,
                            tooltip: '删除此条',
                            onTap: () => _deleteAt(index),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              Text.rich(
                isUser
                    ? TextSpan(
                        text: m.text,
                        style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.6,
                            color: Tokens.textPrimary))
                    : TextSpan(
                        children: [
                          ..._buildSpans(m.text),
                          if (_streaming && m.text.isNotEmpty)
                            TextSpan(
                              text: '▍',
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: Tokens.brandBlue),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 渲染回答中的 [n] 引用为可点击 chip，点击悬浮原文
  List<InlineSpan> _buildSpans(String text) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\[(\d+)\]');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final id = m.group(1)!;
      final hasChunk = _chunkMap.containsKey(id);
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: GestureDetector(
          onTap: hasChunk ? () => _showCitation(id) : null,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: hasChunk
                  ? Tokens.brandBlue.withValues(alpha: 0.12)
                  : Tokens.textTertiary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: hasChunk
                    ? Tokens.brandBlue.withValues(alpha: 0.35)
                    : Colors.transparent,
              ),
            ),
            child: Text('[$id]',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: hasChunk ? Tokens.brandBlue : Tokens.textTertiary)),
          ),
        ),
      ));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    if (spans.isEmpty) spans.add(TextSpan(text: text));
    return spans;
  }

  void _showCitation(String id) {
    final content = _chunkMap[id] ?? '（无法定位该引用）';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        content: GlassCard(
          radius: 24,
          blur: 30,
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: 480,
            height: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.format_quote_rounded,
                        size: 18, color: Tokens.brandBlue),
                    const SizedBox(width: 8),
                    Text('引用原文 · #$id',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Tokens.textPrimary)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close_rounded,
                          size: 18, color: Tokens.textTertiary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(content,
                        style: const TextStyle(
                            fontSize: 13,
                            height: 1.6,
                            color: Tokens.textSecondary)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Tokens.brandBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: Tokens.textSecondary),
        ),
      ),
    );
  }

  Widget _inputBar() {
    final nb = Repo.i.notebook(widget.notebookId);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: Tokens.brandBlue.withValues(alpha: 0.16), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Tokens.brandBlue.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          if (nb.chatMessages.isNotEmpty)
            GestureDetector(
              onTap: _confirmClear,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Tooltip(
                  message: '清空对话',
                  child: Icon(Icons.delete_sweep_rounded,
                      size: 20, color: Tokens.textTertiary),
                ),
              ),
            ),
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_streaming,
              maxLines: 1,
              cursorColor: Tokens.brandBlue,
              style: const TextStyle(color: Tokens.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: '基于 ${_usedChunks == 0 ? '材料' : '$_usedChunks 个分块'} 提问…',
                hintStyle: TextStyle(color: Tokens.textTertiary),
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          if (_streaming)
            GestureDetector(
              onTap: _stop,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(Icons.stop_circle_rounded,
                    size: 28, color: Tokens.danger),
              ),
            )
          else
            GestureDetector(
              onTap: _send,
              child: Container(
                margin: const EdgeInsets.all(6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: Tokens.brandGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.send_rounded,
                    size: 18, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
