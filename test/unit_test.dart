import 'package:flutter_test/flutter_test.dart';
import 'package:dieci/ai/validator.dart';
import 'package:dieci/data/chunker.dart';
import 'package:dieci/models/models.dart';

void main() {
  group('Chunker 切分', () {
    test('段落合并到 ~700 字符', () {
      final text = List.generate(60, (i) => '第 ${i + 1} 段：' + '词' * 20).join('\n\n');
      final chunks = Chunker.chunkText(text, sourceName: 't');
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.text.trim(), isNotEmpty);
        expect(c.sourceName, 't');
      }
      // 拼接回来应包含全部内容
      final joined = chunks.map((c) => c.text).join();
      expect(joined.contains('第 1 段：'), isTrue);
      expect(joined.contains('第 60 段：'), isTrue);
    });

    test('超长段落被硬切且带重叠', () {
      final text = '甲' * 3000;
      final chunks = Chunker.chunkText(text);
      expect(chunks.length, greaterThanOrEqualTo(3));
      expect(chunks.first.text.length, lessThanOrEqualTo(1500));
    });
  });

  group('Chunker 主题聚焦', () {
    test('按关键词打分选出相关块', () {
      final chunks = [
        Chunk(index: 0, text: '神经网络的反向传播算法更新权重'),
        Chunk(index: 1, text: '今天天气很好适合跑步'),
        Chunk(index: 2, text: '梯度消失问题可以通过 ReLU 缓解'),
        Chunk(index: 3, text: '梯度消失是深层网络常见问题'),
      ];
      final hit = Chunker.selectRelevant(chunks, '梯度消失', maxChars: 10000);
      expect(hit.any((c) => c.text.contains('梯度消失')), isTrue);
      expect(hit.any((c) => c.text.contains('跑步')), isFalse);
    });
  });

  group('QuizValidator', () {
    test('判断题答案归一化', () {
      expect(QuizValidator.normalizeTfAnswer('对'), '对');
      expect(QuizValidator.normalizeTfAnswer('错误'), '错');
      expect(QuizValidator.normalizeTfAnswer('true'), '对');
      expect(QuizValidator.normalizeTfAnswer('x'), isNull);
    });

    test('解析合法 JSON', () {
      const json = '''
      [
        {"type":"single","question":"1+1=?","options":["1","2","3","4"],"answer":"2","explain":"基础","difficulty":0.3},
        {"type":"tf","question":"地球是圆的","options":["对","错"],"answer":"对","explain":"常识","difficulty":0.2}
      ]
      ''';
      final qs = QuizValidator.parse(json);
      expect(qs.length, 2);
      expect(qs[0].type, QuestionType.single);
      expect(qs[1].type, QuestionType.tf);
    });

    test('题量与题型一致性校验', () {
      final qs = [
        Question(id: '1', type: QuestionType.single, question: 'a', options: ['1', '2'], answer: '1', explain: 'x'),
        Question(id: '2', type: QuestionType.tf, question: 'b', options: ['对', '错'], answer: '对', explain: 'x'),
      ];
      final req = QuizRequest(
        types: {QuestionType.single, QuestionType.tf},
        totalCount: 2,
        difficulty: '中等',
        keywords: '',
        scope: '全部',
      );
      expect(QuizValidator.validate(qs, req), isEmpty);
    });

    test('题量不符时报错', () {
      final qs = [
        Question(id: '1', type: QuestionType.single, question: 'a', options: ['1', '2'], answer: '1', explain: 'x'),
      ];
      final req = QuizRequest(
        types: {QuestionType.single},
        totalCount: 5,
        difficulty: '中等',
        keywords: '',
        scope: '全部',
      );
      final errs = QuizValidator.validate(qs, req);
      expect(errs.any((e) => e.contains('题量不符')), isTrue);
    });

    test('单选答案不在选项中时报错', () {
      final qs = [
        Question(id: '1', type: QuestionType.single, question: 'a', options: ['1', '2'], answer: '9', explain: 'x'),
      ];
      final req = QuizRequest(
        types: {QuestionType.single},
        totalCount: 1,
        difficulty: '中等',
        keywords: '',
        scope: '全部',
      );
      final errs = QuizValidator.validate(qs, req);
      expect(errs.any((e) => e.contains('答案不在选项中')), isTrue);
    });
  });
}
