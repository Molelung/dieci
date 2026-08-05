import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/glass_chip.dart';
import '../../core/widgets/hero_art.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import 'practice_page.dart';

class ReviewPage extends StatefulWidget {
  final String notebookId;

  const ReviewPage({super.key, required this.notebookId});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  bool _flashMode = false;
  bool _scopeMistakes = true;
  bool _shuffle = false;
  bool _todayOnly = false;
  QuestionType? _mistakeFilter;

  // 闪卡会话状态
  List<Question> _deck = [];
  List<Question> _wrong = [];
  int _index = 0;
  bool _flipped = false;
  int _good = 0;
  bool _sessionDone = false;
  String? _expandedMistakeId;

  void _startFlash(Notebook nb) {
    final pool = _scopeMistakes
        ? nb.mistakes.map((m) => m.question).toList()
        : List<Question>.from(nb.questions);
    if (pool.isEmpty) {
      _toast(_scopeMistakes ? '还没有错题，先去刷题吧' : '还没有题目，先去生成吧');
      return;
    }
    if (_shuffle) pool.shuffle();
    setState(() {
      _deck = List.of(pool);
      _wrong = [];
      _index = 0;
      _flipped = false;
      _good = 0;
      _sessionDone = false;
    });
  }

  void _answer(bool know) {
    if (know) {
      _good++;
    } else {
      _wrong.add(_deck[_index]);
      // 越错越练：不会的题目自动写回错题本（去重）
      final nb = Repo.i.notebook(widget.notebookId);
      final q = _deck[_index];
      Repo.i.addMistake(nb, q);
    }
    if (_index + 1 >= _deck.length) {
      setState(() {
        _index = 0;
        _sessionDone = true;
      });
    } else {
      setState(() {
        _index++;
        _flipped = false;
      });
    }
  }

  void _masterMistake(Notebook nb, String id) {
    nb.mistakes.removeWhere((m) => m.questionId == id);
    Repo.i.save();
    _toast('已移出错题本');
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
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
              child: Row(
                children: [
                  GlassChip(
                    label: '错题本',
                    selected: !_flashMode,
                    onTap: () => setState(() => _flashMode = false),
                  ),
                  const SizedBox(width: 8),
                  GlassChip(
                    label: '闪卡',
                    selected: _flashMode,
                    onTap: () => setState(() => _flashMode = true),
                  ),
                  const Spacer(),
                  if (_flashMode)
                    Text('${_good} 会 / ${_wrong.length} 不会',
                        style: const TextStyle(
                            fontSize: 12, color: Tokens.textSecondary)),
                ],
              ),
            ),
            Expanded(
              child: _flashMode ? _flashPanel(nb) : _mistakePanel(nb),
            ),
          ],
        );
      },
    );
  }

  // ── 错题本 ──────────────────────────────────────────────
  Widget _statsCard(Notebook nb) {
    final now = DateTime.now();
    final today = nb.mistakes.where((m) {
      final d = DateTime.tryParse(m.answeredAt);
      if (d == null) return false;
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).length;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 20,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _stat('${nb.mistakes.length}', '累计错题'),
          _stat('$today', '今日新增'),
          _stat('${nb.questions.length}', '题库题量'),
          if (nb.mistakes.isNotEmpty)
            GlassButton(
              label: '错题→闪卡',
              icon: Icons.style_rounded,
              style: GlassButtonStyle.ghost,
              onPressed: () {
                setState(() {
                  _flashMode = true;
                  _scopeMistakes = true;
                });
                _startFlash(nb);
              },
            ),
          if (nb.mistakes.isNotEmpty)
            GlassButton(
              label: '全部重做',
              icon: Icons.replay_rounded,
              style: GlassButtonStyle.outline,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PracticePage(
                    notebookId: widget.notebookId,
                    presetMistakeIds:
                        nb.mistakes.map((m) => m.questionId).toList(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Tokens.textPrimary)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Tokens.textTertiary)),
      ],
    );
  }

  Widget _filterBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          GlassChip(
            label: '全部',
            selected: _mistakeFilter == null && !_todayOnly,
            onTap: () => setState(() {
              _mistakeFilter = null;
              _todayOnly = false;
            }),
          ),
          GlassChip(
            label: '仅今天',
            selected: _todayOnly,
            onTap: () => setState(() {
              _todayOnly = !_todayOnly;
              if (_todayOnly) _mistakeFilter = null;
            }),
          ),
          for (final (t, label) in const [
            (QuestionType.single, '单选'),
            (QuestionType.multi, '多选'),
            (QuestionType.tf, '判断'),
            (QuestionType.short, '简答'),
          ])
            GlassChip(
              label: label,
              selected: _mistakeFilter == t && !_todayOnly,
              onTap: () => setState(() {
                if (_todayOnly) {
                  _todayOnly = false;
                  _mistakeFilter = t;
                } else {
                  _mistakeFilter = _mistakeFilter == t ? null : t;
                }
              }),
            ),
        ],
      ),
    );
  }

  Widget _mistakePanel(Notebook nb) {
    if (nb.mistakes.isEmpty) {
      return Center(
        child: GlassCard(
          glow: true,
          margin: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HeroArt(icon: Icons.task_alt_rounded, size: 84),
                const SizedBox(height: 16),
                const Text('暂无错题',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Tokens.textPrimary)),
                const SizedBox(height: 8),
                const Text('去「刷题」页做几道题，答错的会自动收进这里，\n复习时一目了然。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, height: 1.7, color: Tokens.textSecondary)),
              ],
            ),
          ),
        ),
      );
    }

    final filtered = nb.mistakes.where((m) {
      if (_todayOnly) {
        final d = DateTime.tryParse(m.answeredAt);
        if (d == null) return false;
        final now = DateTime.now();
        if (d.year != now.year ||
            d.month != now.month ||
            d.day != now.day) {
          return false;
        }
      }
      if (_mistakeFilter != null && m.question.type != _mistakeFilter) {
        return false;
      }
      return true;
    }).toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: 2 + (filtered.isEmpty ? 1 : filtered.length),
      itemBuilder: (context, i) {
        if (i == 0) return _statsCard(nb);
        if (i == 1) return _filterBar();
        if (filtered.isEmpty) {
          return GlassCard(
            margin: const EdgeInsets.only(bottom: 10),
            child: const Row(
              children: [
                Icon(Icons.inbox_rounded, size: 18, color: Tokens.textTertiary),
                SizedBox(width: 10),
                Expanded(
                  child: Text('该题型暂无错题',
                      style: TextStyle(
                          fontSize: 13, color: Tokens.textTertiary)),
                ),
              ],
            ),
          );
        }
        final m = filtered[i - 2];
        final q = m.question;
        final expanded = _expandedMistakeId == m.questionId;
        return GlassCard(
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => setState(() {
                  _expandedMistakeId = expanded ? null : m.questionId;
                }),
                child: Row(
                  children: [
                    _typeBadge(q.type),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            q.question,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: Tokens.textPrimary),
                          ),
                          Text(_relativeTime(m.answeredAt),
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: Tokens.textTertiary)),
                        ],
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: Tokens.textTertiary,
                    ),
                  ],
                ),
              ),
              if (expanded) ...[
                const SizedBox(height: 10),
                if (q.options.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final o in q.options)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Tokens.brandBlue
                                      .withValues(alpha: 0.12)),
                            ),
                            child: Text(o,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Tokens.textSecondary)),
                          ),
                      ],
                    ),
                  ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Tokens.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Tokens.success.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('答案：${q.answer}',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Tokens.success)),
                      const SizedBox(height: 5),
                      Text(q.explain,
                          style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.6,
                              color: Tokens.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    GlassButton(
                      label: '加入闪卡复习',
                      icon: Icons.style_rounded,
                      style: GlassButtonStyle.ghost,
                      onPressed: () {
                        setState(() {
                          _flashMode = true;
                          _scopeMistakes = true;
                        });
                        _startFlash(nb);
                      },
                    ),
                    const SizedBox(width: 8),
                    GlassButton(
                      label: '重做',
                      icon: Icons.replay_rounded,
                      style: GlassButtonStyle.ghost,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PracticePage(
                            notebookId: widget.notebookId,
                            presetMistakeIds: [m.questionId],
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    GlassButton(
                      label: '已掌握',
                      icon: Icons.check_rounded,
                      style: GlassButtonStyle.outline,
                      onPressed: () => _masterMistake(nb, m.questionId),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── 闪卡 ────────────────────────────────────────────────
  Widget _flashPanel(Notebook nb) {
    if (_sessionDone && _deck.isNotEmpty) {
      return _flashSummary(nb);
    }
    if (_deck.isEmpty) {
      return Center(
        child: GlassCard(
          glow: true,
          margin: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HeroArt(icon: Icons.style_rounded, size: 84),
                const SizedBox(height: 16),
                const Text('闪卡复习',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Tokens.textPrimary)),
                const SizedBox(height: 8),
                const Text('选择题目来源，翻卡片回忆，用「会 / 不会」反馈，\n不会的卡片会自动加回队列再来一轮。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, height: 1.7, color: Tokens.textSecondary)),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlassChip(
                      label: '错题',
                      selected: _scopeMistakes,
                      onTap: () => setState(() => _scopeMistakes = true),
                    ),
                    const SizedBox(width: 8),
                    GlassChip(
                      label: '全部题目',
                      selected: !_scopeMistakes,
                      onTap: () => setState(() => _scopeMistakes = false),
                    ),
                    const SizedBox(width: 8),
                    GlassChip(
                      label: '随机顺序',
                      selected: _shuffle,
                      onTap: () => setState(() => _shuffle = !_shuffle),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GlassButton(
                  label: '开始复习',
                  icon: Icons.play_arrow_rounded,
                  onPressed: () => _startFlash(nb),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final q = _deck[_index];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              Text('第 ${_index + 1} / ${_deck.length} 张',
                  style: const TextStyle(
                      fontSize: 12, color: Tokens.textSecondary)),
              const Spacer(),
              Text('本轮已掌握 $_good 张',
                  style: const TextStyle(
                      fontSize: 12, color: Tokens.textTertiary)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_index + 1) / _deck.length,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.6),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Tokens.brandBlue),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _FlipCard(
              question: q,
              flipped: _flipped,
              onFlip: () => setState(() => _flipped = !_flipped),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GlassButton(
                  label: '不会（稍后再来）',
                  icon: Icons.replay_rounded,
                  style: GlassButtonStyle.outline,
                  onPressed: () => _answer(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlassButton(
                  label: '会了',
                  icon: Icons.check_rounded,
                  onPressed: () => _answer(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _flashSummary(Notebook nb) {
    return Center(
      child: GlassCard(
        glow: true,
        margin: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HeroArt(
                icon: _wrong.isEmpty
                    ? Icons.emoji_events_rounded
                    : Icons.replay_rounded,
              ),
              const SizedBox(height: 16),
              Text(
                _wrong.isEmpty ? '全部掌握！' : '本轮完成，还有 ${_wrong.length} 张需要巩固',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Tokens.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                '掌握了 $_good 张 · 需巩固 ${_wrong.length} 张${_wrong.isNotEmpty ? '（已写回错题本）' : ''}',
                style: const TextStyle(
                    fontSize: 13, color: Tokens.textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_wrong.isEmpty && _scopeMistakes)
                    GlassButton(
                      label: '已掌握错题全部移出',
                      icon: Icons.cleaning_services_rounded,
                      style: GlassButtonStyle.ghost,
                      onPressed: () {
                        final nb = Repo.i.notebook(widget.notebookId);
                        final ids = _deck.map((q) => q.id).toSet();
                        final before = nb.mistakes.length;
                        nb.mistakes
                            .removeWhere((m) => ids.contains(m.questionId));
                        Repo.i.save();
                        _toast('已移出 ${before - nb.mistakes.length} 道已掌握错题');
                      },
                    ),
                  if (_wrong.isEmpty && _scopeMistakes) const SizedBox(width: 10),
                  GlassButton(
                    label: '再来一轮',
                    icon: Icons.refresh_rounded,
                    onPressed: () {
                      setState(() {
                        _sessionDone = false;
                        _index = 0;
                        _flipped = false;
                        _wrong = [];
                        _good = 0;
                      });
                    },
                  ),
                  if (_wrong.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    GlassButton(
                      label: '只看不会的',
                      style: GlassButtonStyle.outline,
                      onPressed: () {
                        setState(() {
                          _deck = List.of(_wrong);
                          _wrong = [];
                          _index = 0;
                          _sessionDone = false;
                          _flipped = false;
                          _good = 0;
                        });
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _relativeTime(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final diff = DateTime.now().difference(d.toLocal());
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _FlipCard extends StatelessWidget {
  final Question question;
  final bool flipped;
  final VoidCallback onFlip;

  const _FlipCard({
    required this.question,
    required this.flipped,
    required this.onFlip,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onFlip,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: flipped ? 1 : 0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        builder: (context, t, child) {
          final angle = t * math.pi;
          final showBack = t >= 0.5;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angle),
            child: showBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: _face(
                      gradient: const LinearGradient(
                        colors: [Tokens.brandBlue, Tokens.brandIndigo],
                      ),
                      icon: Icons.lightbulb_rounded,
                      main: question.answer,
                      sub: question.explain,
                    ),
                  )
                : _face(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF5AC8FA), Color(0xFF2E7CF6)],
                    ),
                    icon: Icons.help_outline_rounded,
                    main: question.question,
                    sub: question.options.isNotEmpty
                        ? question.options.take(4).join('　|　')
                        : '点击翻面查看答案',
                  ),
          );
        },
      ),
    );
  }

  Widget _face({
    required Gradient gradient,
    required IconData icon,
    required String main,
    required String sub,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Tokens.brandBlue.withValues(alpha: 0.30),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 34, color: Colors.white70),
          const SizedBox(height: 18),
          Text(
            main,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              height: 1.6,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('点击翻面',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}
