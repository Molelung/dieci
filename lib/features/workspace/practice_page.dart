import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../ai/gemini_client.dart';
import '../../ai/prompts.dart';
import '../../ai/validator.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/error_toast.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/glass_chip.dart';
import '../../core/widgets/glass_input.dart';
import '../../data/chunker.dart';
import '../../data/repository.dart';
import '../../data/settings_store.dart';
import '../../models/models.dart';
import '../../features/settings/settings_page.dart';

class PracticePage extends StatefulWidget {
  final String notebookId;
  final List<String>? presetScope;
  final String? presetSourceId;
  final List<String>? presetMistakeIds;

  const PracticePage({
    super.key,
    required this.notebookId,
    this.presetScope,
    this.presetSourceId,
    this.presetMistakeIds,
  });

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  final _keywordController = TextEditingController();
  final _shortAnswers = <String, String>{};
  final _scroll = ScrollController();

  final Set<QuestionType> _types = {QuestionType.single, QuestionType.tf};
  String _difficulty = '中等';
  int _count = 10;
  int _round = 0;
  bool _generating = false;
  bool _presetMode = false;
  CancelToken? _cancel;
  Timer? _timer;
  Stopwatch _stopwatch = Stopwatch();
  String _elapsed = '00:00';
  List<String> _errors = [];
  List<Question> _questions = [];
  Map<String, dynamic> _answers = {}; // qid -> String | Set<String>
  Map<String, bool> _selfAssessed = {};
  bool _submitted = false;
  int _score = 0;
  String? _scopeName;

  static const _schema = {
    'type': 'ARRAY',
    'items': {
      'type': 'OBJECT',
      'properties': {
        'type': {'type': 'STRING', 'enum': ['single', 'multi', 'tf', 'short']},
        'question': {'type': 'STRING'},
        'options': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
        'answer': {'type': 'STRING'},
        'explain': {'type': 'STRING'},
        'difficulty': {'type': 'NUMBER'},
        'citation': {'type': 'STRING'},
      },
      'required': ['type', 'question', 'options', 'answer', 'explain'],
    },
  };

  @override
  void initState() {
    super.initState();
    final nb = Repo.i.notebook(widget.notebookId);
    if (widget.presetMistakeIds != null && widget.presetMistakeIds!.isNotEmpty) {      // 错题重做模式：直接从错题本加载，无需 AI 生成
      final ids = widget.presetMistakeIds!.toSet();
      _questions = nb.mistakes
          .where((m) => ids.contains(m.questionId))
          .map((m) => m.question)
          .toList();
      _presetMode = true;
      _scopeName = '错题重做（${_questions.length} 题）';
      _startTimer();
    } else if (widget.presetSourceId != null) {
      final src = nb.sources
          .where((s) => s.id == widget.presetSourceId)
          .firstOrNull;
      _scopeName = src?.name ?? '对话内容';
    } else if (widget.presetScope != null && widget.presetScope!.isNotEmpty) {
      _scopeName = '已勾选大纲节点（${widget.presetScope!.length} 个）';
    } else {
      _scopeName = '全部材料';
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _timer?.cancel();
    _keywordController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpTo(int index) {
    if (!_scroll.hasClients) return;
    // 近似定位：每张卡片约占 180px（含间距），跳转后由用户微调
    _scroll.animateTo(
      (index * 190.0).clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _stopwatch
      ..reset()
      ..start();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _submitted) {
        t.cancel();
        return;
      }
      final m =
          _stopwatch.elapsed.inMinutes.toString().padLeft(2, '0');
      final s =
          (_stopwatch.elapsed.inSeconds % 60).toString().padLeft(2, '0');
      final text = '$m:$s';
      if (text != _elapsed) setState(() => _elapsed = text);
    });
  }

  String _buildMaterial(Notebook nb) {
    if (widget.presetSourceId != null) {
      final src = nb.sources
          .where((s) => s.id == widget.presetSourceId)
          .firstOrNull;
      return src?.rawText ?? '';
    }
    final chunks = nb.sources
        .expand((s) => s.chunks ?? <Chunk>[])
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final relevant = Chunker.selectRelevant(
        chunks, _keywordController.text.trim(),
        maxChars: 8000);
    return relevant.map((c) => '[${c.index}] ${c.text}').join('\n\n');
  }

  Future<void> _generate() async {
    if (_presetMode) {
      _toast('错题重做模式已锁定，直接作答即可');
      return;
    }
    if (_types.isEmpty) {
      _toast('至少选择一种题型');
      return;
    }
    final nb = Repo.i.notebook(widget.notebookId);
    if (nb.sources.isEmpty) {
      _toast('没有学习材料，请先到「来源」页导入');
      return;
    }

    final req = QuizRequest(
      types: _types,
      totalCount: _count,
      difficulty: _difficulty,
      keywords: _keywordController.text.trim(),
      scope: _scopeName ?? '全部材料',
    );
    final material = _buildMaterial(nb);
    if (material.trim().isEmpty) {
      _toast('材料为空');
      return;
    }

    final client = GeminiClient(SettingsStore.i);
    setState(() {
      _generating = true;
      _round = 0;
      _errors = [];
      _questions = [];
      _answers = {};
      _selfAssessed = {};
      _submitted = false;
    });
    _startTimer();

    var current = req;
    var round = 0;
    List<Question>? result;
    List<String>? lastErrors;
    while (round <= QuizValidator.maxRetries) {
      if (!mounted) return;
      setState(() {
        _round = round;
        _generating = true;
      });

      final userParts = [
        Prompts.quizUser(
          scope: current.scope,
          typesLine: current.typesLine,
          count: current.totalCount,
          difficulty: current.difficulty,
          keywords: current.keywords,
          material: material,
        ),
        if (lastErrors != null && lastErrors.isNotEmpty)
          Prompts.quizRetry(lastErrors),
      ];

      final sb = StringBuffer();
      _cancel = CancelToken();
      try {
        await for (final delta in client.streamGenerate(
          contents: [AiMessage('user', userParts.join('\n'))],
          system: Prompts.quizSystem(),
          temperature: 0.3,
          maxTokens: 8192,
          responseSchema: _schema,
          cancelToken: _cancel,
        )) {
          sb.write(delta);
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _generating = false;
          _errors = ['请求失败：$e'];
        });
        showAiError(
          context,
          '$e',
          onSettings: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsPage()),
          ),
        );
        return;
      }

      try {
        result = QuizValidator.parse(sb.toString());
        lastErrors = QuizValidator.validate(result, current);
      } catch (e) {
        lastErrors = ['JSON 解析失败：$e，请严格按 Schema 输出'];
      }

      if (lastErrors.isEmpty) break;
      round++;
      if (round > QuizValidator.maxRetries) {
        setState(() {
          _generating = false;
          _errors = lastErrors!;
        });
        return;
      }
    }

    if (!mounted || result == null) return;
    setState(() {
      _generating = false;
      _questions = result!;
      _errors = [];
    });
    _toast('生成完成：${_questions.length} 题');
  }

  Future<void> _submit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        content: GlassCard(
          radius: 24,
          blur: 30,
          padding: const EdgeInsets.all(22),
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.task_alt_rounded,
                    size: 34, color: Tokens.brandBlue),
                const SizedBox(height: 12),
                const Text('确认交卷？',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Tokens.textPrimary)),
                const SizedBox(height: 8),
                Text('已作答 ${_answeredCount()} / ${_questions.length} 题，用时 $_elapsed',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.6,
                        color: Tokens.textSecondary)),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GlassButton(
                      label: '再想想',
                      style: GlassButtonStyle.ghost,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                    const SizedBox(width: 10),
                    GlassButton(
                      label: '交卷',
                      icon: Icons.check_rounded,
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
    if (confirmed != true || !mounted) return;
    _submitNow();
  }

  void _submitNow() {
    var correct = 0;
    for (final q in _questions) {
      final a = _answers[q.id];
      if (a == null) continue;
      switch (q.type) {
        case QuestionType.single:
        case QuestionType.tf:
          if (a.toString().trim() == q.answer.trim()) correct++;
        case QuestionType.multi:
          final set = (a as Set<String>).map((e) => e.trim()).toSet();
          final expected =
              q.answer.split('、').map((e) => e.trim()).toSet();
          if (set.length == expected.length && set.containsAll(expected)) {
            correct++;
          }
        case QuestionType.short:
          if (_selfAssessed[q.id] == true) correct++;
      }
    }
    final nb = Repo.i.notebook(widget.notebookId);
    if (_presetMode) {
      // 重做模式：答对的移出错题本，答错的保留
      for (final q in _questions) {
        final idx = nb.mistakes.indexWhere((m) => m.questionId == q.id);
        if (idx == -1) continue;
        if (_isCorrect(q)) nb.mistakes.removeAt(idx);
      }
    } else {
      for (final q in _questions) {
        if (!_isCorrect(q)) {
          nb.mistakes.insert(
            0,
            Mistake(
              questionId: q.id,
              questionJson: jsonEncode(q.toJson()),
              answeredAt: DateTime.now().toIso8601String(),
            ),
          );
        }
      }
    }
    Repo.i.save();
    _stopwatch.stop();
    setState(() {
      _submitted = true;
      _score = correct;
    });
  }

  bool _isCorrect(Question q) {
    final a = _answers[q.id];
    if (a == null) return false;
    switch (q.type) {
      case QuestionType.single:
      case QuestionType.tf:
        return a.toString().trim() == q.answer.trim();
      case QuestionType.multi:
        final set = (a as Set<String>).map((e) => e.trim()).toSet();
        final expected = q.answer.split('、').map((e) => e.trim()).toSet();
        return set.length == expected.length && set.containsAll(expected);
      case QuestionType.short:
        return _selfAssessed[q.id] == true;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        _paramCard(),
        _submitBar(),
        if (_questions.length >= 6) _jumpRow(),
        if (_errors.isNotEmpty) _errorCard(),
        if (_generating) _generatingCard(),
        if (_submitted) _resultBanner(),
        for (var i = 0; i < _questions.length; i++)
          _questionCard(_questions[i], index: i),
      ],
    );
  }

  Widget _paramCard() {
    if (_presetMode) {
      return GlassCard(
        margin: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            const Icon(Icons.replay_rounded, size: 20, color: Tokens.brandBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '错题重做：共 ${_questions.length} 题，答对即自动移出错题本。',
                style: const TextStyle(
                    fontSize: 13, color: Tokens.textSecondary),
              ),
            ),
          ],
        ),
      );
    }
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 17, color: Tokens.brandBlue),
              const SizedBox(width: 8),
              const Text('出题要求（AI 将严格遵循）',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Tokens.textPrimary)),
              const Spacer(),
              Text('范围：$_scopeName',
                  style: const TextStyle(
                      fontSize: 11, color: Tokens.textTertiary)),
            ],
          ),
          const SizedBox(height: 14),
          const Text('题型（可多选）',
              style: TextStyle(fontSize: 12, color: Tokens.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (t, label) in const [
                (QuestionType.single, '单选'),
                (QuestionType.multi, '多选'),
                (QuestionType.tf, '判断'),
                (QuestionType.short, '简答'),
              ])
                GlassChip(
                  label: label,
                  selected: _types.contains(t),
                  onTap: () => setState(() {
                    if (_types.contains(t)) {
                      _types.remove(t);
                    } else {
                      _types.add(t);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('题量',
                  style: TextStyle(fontSize: 12, color: Tokens.textSecondary)),
              const SizedBox(width: 12),
              Expanded(
                  child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: Tokens.brandBlue,
                    thumbColor: Tokens.brandBlue,
                    inactiveTrackColor:
                        Tokens.brandBlue.withValues(alpha: 0.10),
                    overlayColor: Tokens.brandBlue.withValues(alpha: 0.12),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: _count.toDouble(),
                    min: 5,
                    max: 30,
                    divisions: 25,
                    label: '$_count',
                    onChanged: _generating
                        ? null
                        : (v) => setState(() => _count = v.round()),
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text('$_count 题',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Tokens.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('难度',
              style: TextStyle(fontSize: 12, color: Tokens.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final d in const ['简单', '中等', '困难'])
                GlassChip(
                  label: d,
                  selected: _difficulty == d,
                  selectedColor: Tokens.brandBlue,
                  onTap: () => setState(() => _difficulty = d),
                ),
            ],
          ),
          const SizedBox(height: 14),
          GlassInput(
            controller: _keywordController,
            hint: '必考考点词，多个用空格分隔（可选）',
            icon: Icons.track_changes_rounded,
          ),
          const SizedBox(height: 14),
          GlassButton(
            label: _generating ? '生成中…（第 ${_round + 1} 轮）' : '生成题目',
            icon: Icons.auto_awesome_rounded,
            loading: _generating,
            onPressed: _generating ? null : _generate,
          ),
        ],
      ),
    );
  }

  Widget _generatingCard() {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('正在生成题目…',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Tokens.textPrimary)),
                const SizedBox(height: 3),
                Text(
                  _round == 0
                      ? 'AI 严格按题型、题量、难度要求输出'
                      : '第 ${_round + 1} 轮：校验未通过，正在自动修正',
                  style: const TextStyle(
                      fontSize: 11, color: Tokens.textTertiary),
                ),
              ],
            ),
          ),
          if (_round > 0)
            Icon(Icons.autorenew_rounded,
                size: 16, color: Tokens.brandBlue.withValues(alpha: 0.8)),
        ],
      ),
    );
  }

  Widget _jumpRow() {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SizedBox(
        height: 30,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _questions.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, i) => GestureDetector(
            onTap: () => _jumpTo(i),
            child: Container(
              width: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: _answers[_questions[i].id] != null
                    ? Tokens.brandBlue.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.75),
                border: Border.all(
                  color: Tokens.brandBlue.withValues(alpha: 0.18),
                ),
              ),
              child: Text('${i + 1}',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _answers[_questions[i].id] != null
                          ? Tokens.brandBlue
                          : Tokens.textSecondary)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorCard() {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      fill: Tokens.danger.withValues(alpha: 0.10),
      borderOpacity: 0.3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('生成未通过校验，可调整要求后重试',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Tokens.danger)),
          const SizedBox(height: 6),
          for (final e in _errors)
            Text('• $e',
                style: const TextStyle(
                    fontSize: 12, color: Tokens.textSecondary, height: 1.5)),
        ],
      ),
    );
  }

  Widget _resultBanner() {
    final total = _questions.length;
    final passed = _score;
    final pct = total == 0 ? 0 : (passed / total * 100).round();
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      glow: true,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: pct >= 60 ? Tokens.brandGradient : const LinearGradient(
                  colors: [Tokens.danger, Color(0xFFFF9A62)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text('$pct%',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('得分 $passed / $total',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Tokens.textPrimary)),
                const SizedBox(height: 3),
                Text(
                  '用时 $_elapsed · ${pct >= 90 ? '掌握得很好！错题已进错题本' : pct >= 60 ? '继续加油，错题已自动进错题本' : '建议回到大纲复习后重刷，错题已记录'}',
                  style: const TextStyle(
                      fontSize: 12, color: Tokens.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _questionCard(Question q, {required int index}) {
    final submitted = _submitted;
    final isCorrect = _isCorrect(q);
    final answered = _answers[q.id] != null ||
        (q.type == QuestionType.short &&
            (_shortAnswers[q.id]?.isNotEmpty ?? false)) ||
        (q.type == QuestionType.short && _selfAssessed[q.id] != null);

    final Color? badgeColor = submitted
        ? (isCorrect ? Tokens.success : Tokens.danger)
        : null;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      borderGradient: badgeColor == null
          ? null
          : LinearGradient(colors: [
              badgeColor.withValues(alpha: 0.5),
              badgeColor.withValues(alpha: 0.15),
            ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _typeBadge(q.type),
              const SizedBox(width: 8),
              Text('第 ${index + 1} 题',
                  style: const TextStyle(
                      fontSize: 11, color: Tokens.textTertiary)),
              const SizedBox(width: 8),
              if (q.difficulty > 0.66)
                const Text('困难', style: TextStyle(fontSize: 10, color: Tokens.danger)),
              if (q.difficulty > 0.33 && q.difficulty <= 0.66)
                const Text('中等', style: TextStyle(fontSize: 10, color: Tokens.warn)),
              const Spacer(),
              if (submitted)
                Icon(
                  isCorrect
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  size: 20,
                  color: badgeColor,
                )
              else if (answered)
                const Icon(Icons.pending_rounded,
                    size: 18, color: Tokens.textTertiary),
            ],
          ),
          const SizedBox(height: 10),
          Text(q.question,
              style: const TextStyle(
                  fontSize: 14.5,
                  height: 1.55,
                  fontWeight: FontWeight.w600,
                  color: Tokens.textPrimary)),
          const SizedBox(height: 12),
          switch (q.type) {
            QuestionType.single => _singleOptions(q),
            QuestionType.multi => _multiOptions(q),
            QuestionType.tf => _tfOptions(q),
            QuestionType.short => _shortAnswer(q),
          },
          if (submitted || _selfAssessed[q.id] != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Tokens.brandBlue.withValues(alpha: 0.10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('答案：${q.answer}',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Tokens.success)),
                  const SizedBox(height: 6),
                  Text(q.explain,
                      style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.6,
                          color: Tokens.textSecondary)),
                  if (q.citation != null && q.citation!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('出处：${q.citation}',
                        style: const TextStyle(
                            fontSize: 11, color: Tokens.textTertiary)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _typeBadge(QuestionType t) {
    final (label, color) = switch (t) {
      QuestionType.single => ('单选', Tokens.brandBlue),
      QuestionType.multi => ('多选', Tokens.brandIndigo),
      QuestionType.tf => ('判断', Tokens.brandCyan),
      QuestionType.short => ('简答', Tokens.success),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _singleOptions(Question q) {
    return Column(
      children: [
        for (final o in q.options)
          _optionRow(
            q,
            text: o,
            selected: _answers[q.id]?.toString() == o,
            onTap: _submitted
                ? null
                : () => setState(() => _answers[q.id] = o),
          ),
      ],
    );
  }

  Widget _multiOptions(Question q) {
    final chosen = (_answers[q.id] as Set<String>?) ?? <String>{};
    return Column(
      children: [
        for (final o in q.options)
          _optionRow(
            q,
            text: o,
            multi: true,
            selected: chosen.contains(o),
            onTap: _submitted
                ? null
                : () => setState(() {
                    if (chosen.contains(o)) {
                      chosen.remove(o);
                    } else {
                      chosen.add(o);
                    }
                    _answers[q.id] = chosen;
                  }),
          ),
      ],
    );
  }

  Widget _tfOptions(Question q) {
    final cur = _answers[q.id]?.toString();
    return Row(
      children: [
        for (final o in const ['对', '错'])
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GlassChip(
              label: o,
              selected: cur == o,
              onTap: _submitted
                  ? null
                  : () => setState(() => _answers[q.id] = o),
            ),
          ),
      ],
    );
  }

  Widget _optionRow(Question q,
      {required String text, bool multi = false, required bool selected, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected
              ? Tokens.brandBlue.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.7),
          border: Border.all(
            color: selected
                ? Tokens.brandBlue.withValues(alpha: 0.55)
                : Tokens.brandBlue.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Icon(
              multi
                  ? (selected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded)
                  : (selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded),
              size: 17,
              color: selected ? Tokens.brandBlue : Tokens.textTertiary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 13.5, height: 1.4, color: Tokens.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shortAnswer(Question q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassInput(
          hint: '输入你的答案…',
          maxLines: 3,
          onChanged: (v) => _shortAnswers[q.id] = v,
        ),
        if (!_submitted) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              GlassButton(
                label: '对答案',
                icon: Icons.visibility_rounded,
                style: GlassButtonStyle.outline,
                onPressed: () => setState(() => _selfAssessed[q.id] = false),
              ),
              if (_selfAssessed[q.id] != null)
                Wrap(
                  spacing: 8,
                  children: [
                    GlassChip(
                      label: '我答对了',
                      selected: _selfAssessed[q.id] == true,
                      selectedColor: Tokens.success,
                      onTap: () =>
                          setState(() => _selfAssessed[q.id] = true),
                    ),
                    GlassChip(
                      label: '我答错了',
                      selected: _selfAssessed[q.id] == false,
                      selectedColor: Tokens.danger,
                      onTap: () =>
                          setState(() => _selfAssessed[q.id] = false),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _submitBar() {
    if (_questions.isEmpty || _submitted) return const SizedBox.shrink();
    final answered = _answeredCount();
    final allDone = answered == _questions.length;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          const Icon(Icons.timer_rounded, size: 16, color: Tokens.brandBlue),
          const SizedBox(width: 6),
          Text(_elapsed,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Tokens.textPrimary)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              allDone
                  ? '已全部作答，可以交卷了'
                  : '已作答 $answered / ${_questions.length}',
              style: TextStyle(
                  fontSize: 12,
                  color: allDone ? Tokens.success : Tokens.textSecondary),
            ),
          ),
          GlassButton(
            label: '交卷',
            icon: Icons.task_alt_rounded,
            onPressed: answered == 0 ? null : _submit,
          ),
        ],
      ),
    );
  }

  int _answeredCount() {
    var n = 0;
    for (final q in _questions) {
      if (q.type == QuestionType.short) {
        if (_selfAssessed[q.id] != null) n++;
      } else if (_answers[q.id] != null) {
        n++;
      }
    }
    return n;
  }
}
