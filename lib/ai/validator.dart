import 'dart:convert';
import '../models/models.dart';

/// 出题请求参数（用户面板表单产物）
class QuizRequest {
  final Set<QuestionType> types;
  final int totalCount;
  final String difficulty; // 简单 / 中等 / 困难
  final String keywords;
  final String scope;

  QuizRequest({
    required this.types,
    required this.totalCount,
    required this.difficulty,
    required this.keywords,
    required this.scope,
  });

  String get typesLine {
    final map = {
      QuestionType.single: '单选',
      QuestionType.multi: '多选',
      QuestionType.tf: '判断',
      QuestionType.short: '简答',
    };
    return types.map((t) => map[t]).join('、');
  }
}

/// L4 校验器：题量/题型/答案合法性/字段完整性
class QuizValidator {
  QuizValidator._();

  static const maxRetries = 2;

  static String? normalizeTfAnswer(String a) {
    final s = a.trim();
    if (s == '对' || s == '正确' || s == 'true' || s == 'True' || s == 'A') {
      return '对';
    }
    if (s == '错' || s == '错误' || s == 'false' || s == 'False' || s == 'B') {
      return '错';
    }
    return null;
  }

  /// 返回错误列表，空列表 = 通过
  static List<String> validate(List<Question> questions, QuizRequest req) {
    final errors = <String>[];

    if (questions.isEmpty) {
      errors.add('未解析到任何题目');
      return errors;
    }

    // 题量与题型一致性
    final byType = <QuestionType, int>{};
    for (final q in questions) {
      byType[q.type] = (byType[q.type] ?? 0) + 1;
    }
    final total = questions.length;
    if (total != req.totalCount) {
      errors.add('题量不符：要求 ${req.totalCount} 题，实际 $total 题');
    }

    for (final t in req.types) {
      final expect = req.totalCount ~/ req.types.length +
          (req.types.toList().indexOf(t) < req.totalCount % req.types.length ? 1 : 0);
      final actual = byType[t] ?? 0;
      if (actual != expect) {
        errors.add(
            '题型「${t.name}」数量不符：要求 $expect 题，实际 $actual 题');
      }
    }
    for (final t in byType.keys) {
      if (!req.types.contains(t)) {
        errors.add('出现了未要求的题型「${t.name}」');
      }
    }

    // 单题合法性
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      if (q.question.trim().isEmpty) errors.add('第 ${i + 1} 题题干为空');
      if (q.explain.trim().isEmpty) {
        errors.add('第 ${i + 1} 题缺少解析 explain');
      }
      switch (q.type) {
        case QuestionType.single:
          if (q.options.length < 2) errors.add('第 ${i + 1} 题单选选项不足');
          if (q.answer.isEmpty || !q.options.contains(q.answer)) {
            errors.add('第 ${i + 1} 题单选答案不在选项中');
          }
        case QuestionType.multi:
          final answers = q.answer.split('、').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          if (answers.length < 2) errors.add('第 ${i + 1} 题多选答案少于 2 个');
          for (final a in answers) {
            if (!q.options.contains(a)) errors.add('第 ${i + 1} 题多选答案「$a」不在选项中');
          }
        case QuestionType.tf:
          if (normalizeTfAnswer(q.answer) == null) {
            errors.add('第 ${i + 1} 题判断题答案需为「对/错」');
          }
        case QuestionType.short:
          if (q.answer.trim().isEmpty) errors.add('第 ${i + 1} 题简答缺少参考答案');
      }
    }

    return errors;
  }

  /// 从 Gemini 返回的 JSON 文本解析题目；失败抛异常
  static List<Question> parse(String jsonText) {
    final cleaned = _stripCodeFence(jsonText.trim());
    final dynamic data = jsonDecode(cleaned);
    final list = data is List ? data : (data is Map && data['questions'] is List ? data['questions'] : null);
    if (list == null) throw const FormatException('输出不是题目数组');

    return list.map<Question>((e) {
      final m = e as Map<String, dynamic>;
      return Question(
        id: 'q-${DateTime.now().microsecondsSinceEpoch}-${_rand()}',
        type: _typeOf(m['type']?.toString()),
        question: (m['question'] ?? '').toString().trim(),
        options: (m['options'] as List? ?? []).map((o) => o.toString().trim()).toList(),
        answer: (m['answer'] ?? '').toString().trim(),
        explain: (m['explain'] ?? '').toString().trim(),
        difficulty: (m['difficulty'] as num?)?.toDouble() ?? 0.5,
        citation: m['citation']?.toString(),
      );
    }).toList();
  }

  static String _stripCodeFence(String s) {
    if (s.startsWith('```')) {
      final idx = s.indexOf('\n');
      if (idx != -1) return s.substring(idx + 1).replaceFirst(RegExp(r'```\s*$'), '').trim();
    }
    return s;
  }

  static QuestionType _typeOf(String? t) {
    switch (t) {
      case 'single':
        return QuestionType.single;
      case 'multi':
        return QuestionType.multi;
      case 'tf':
        return QuestionType.tf;
      case 'short':
        return QuestionType.short;
      default:
        return QuestionType.single;
    }
  }

  static int _rand() => DateTime.now().microsecondsSinceEpoch % 100000;
}
