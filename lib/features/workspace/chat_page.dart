import 'dart:async';
import 'package:flutter/material.dart';
import '../../ai/gemini_client.dart';
import '../../ai/prompts.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/hero_art.dart';
import '../../data/chunker.dart';
import '../../data/repository.dart';
import '../../data/settings_store.dart';
import '../../models/models.dart';
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
  StreamSubscription<String>? _sub;
  bool _streaming = false;
  int _usedChunks = 0;

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _streaming) return;

    final nb = Repo.i.notebook(widget.notebookId);
    if (nb.sources.isEmpty) {
      _toast('没有学习材料，请先到「来源」页导入');
      return;
    }

    _controller.clear();
    nb.chatMessages.add(ChatMessage(
      role: 'user',
      text: text,
      createdAt: DateTime.now().toIso8601String(),
    ));

    final chunks = nb.sources
        .expand((s) => s.chunks ?? <Chunk>[])
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final relevant = Chunker.selectRelevant(chunks, text);
    _usedChunks = relevant.length;
    final material = relevant.map((c) => '[${c.index}] ${c.text}').join('\n\n');

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
    try {
      _sub = client
          .streamGenerate(
            contents: [AiMessage('user', Prompts.chatUser(material, text))],
            system: Prompts.chatSystem(),
            temperature: 0.5,
            maxTokens: 2048,
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
                        return _bubble(nb, m);
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

  Widget _bubble(Notebook nb, ChatMessage m) {
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
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              Text(
                m.text,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.6,
                  color: Tokens.textPrimary,
                ),
              ),
            ],
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
