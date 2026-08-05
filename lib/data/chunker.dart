import '../models/models.dart';

class Chunker {
  Chunker._();

  static const int _target = 700;
  static const int _overlap = 80;

  /// 按段落切分文本，合并到 ~700 字符，重叠 80 字符
  static List<Chunk> chunkText(String text, {String? sourceName}) {
    final paragraphs = text
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    final chunks = <Chunk>[];
    final buffer = StringBuffer();
    for (final p in paragraphs) {
      if (buffer.isNotEmpty && buffer.length + p.length > _target) {
        chunks.add(Chunk(
          index: chunks.length,
          text: buffer.toString().trim(),
          sourceName: sourceName,
        ));
        buffer.clear();
        buffer.write(p);
      } else {
        buffer.write((buffer.isNotEmpty ? '\n\n' : '') + p);
      }
      if (buffer.length > _target * 3) {
        chunks.add(Chunk(
          index: chunks.length,
          text: buffer.toString().trim(),
          sourceName: sourceName,
        ));
        buffer.clear();
      }
    }
    if (buffer.isNotEmpty) {
      chunks.add(Chunk(
        index: chunks.length,
        text: buffer.toString().trim(),
        sourceName: sourceName,
      ));
    }

    // 长段落硬切 + 重叠
    final finalChunks = <Chunk>[];
    for (final c in chunks) {
      if (c.text.length <= _target * 1.5) {
        finalChunks.add(c);
        continue;
      }
      var start = 0;
      while (start < c.text.length) {
        var end = (start + _target).clamp(0, c.text.length);
        if (end < c.text.length) {
          final nl = c.text.lastIndexOf('\n', end);
          if (nl > start + _target * 0.6) end = nl;
        }
        finalChunks.add(Chunk(
          index: finalChunks.length,
          text: c.text.substring(start, end).trim(),
          sourceName: sourceName,
        ));
        start = end - _overlap;
        if (start <= 0 || end >= c.text.length) break;
      }
    }
    return finalChunks;
  }

  /// 主题聚焦：按关键词打分选出相关分块（避免无关内容浪费 token）
  static List<Chunk> selectRelevant(
    List<Chunk> chunks,
    String topic, {
    int maxChars = 16000,
  }) {
    if (topic.trim().isEmpty) {
      var acc = 0;
      return chunks
          .where((c) {
            acc += c.text.length;
            return acc <= maxChars;
          })
          .toList();
    }

    final words = topic
        .split(RegExp(r'[\s,，。.;；、/]+'))
        .where((w) => w.trim().isNotEmpty)
        .map((w) => w.trim())
        .toList();
    final bigrams = <String>[];
    final compact = topic.replaceAll(RegExp(r'\s'), '');
    if (compact.length >= 2) {
      for (var i = 0; i + 2 <= compact.length && bigrams.length < 8; i++) {
        bigrams.add(compact.substring(i, i + 2));
      }
    }
    final keys = [...words, ...bigrams].toSet().toList();
    if (keys.isEmpty) keys.add(topic);

    final scored = chunks.map((c) {
      var score = 0;
      for (final k in keys) {
        if (k.isEmpty) continue;
        final count = k.split('').every((ch) => c.text.contains(ch))
            ? _count(c.text, k)
            : 0;
        score += count * (k.length > 1 ? 2 : 1);
      }
      return (chunk: c, score: score);
    }).where((e) => e.score > 0).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    var acc = 0;
    final result = <Chunk>[];
    for (final e in scored) {
      if (acc + e.chunk.text.length > maxChars) break;
      result.add(e.chunk);
      acc += e.chunk.text.length;
      if (result.length >= 15) break;
    }
    if (result.isEmpty) {
      var acc2 = 0;
      result.addAll(chunks.where((c) {
        acc2 += c.text.length;
        return acc2 <= maxChars;
      }));
    }
    result.sort((a, b) => a.index.compareTo(b.index));
    return result;
  }

  static int _count(String text, String key) {
    var n = 0;
    var i = 0;
    while ((i = text.indexOf(key, i)) != -1) {
      n++;
      i += key.length;
    }
    return n;
  }
}
