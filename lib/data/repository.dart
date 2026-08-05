import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../utils/crash_log.dart';
import 'chunker.dart';
import 'storage.dart';

class Repo extends ChangeNotifier {
  Repo._();
  static final Repo i = Repo._();

  List<Notebook> notebooks = [];
  Future<void> _writeQueue = Future.value();

  Future<void> init() async {
    final file = await Storage.notebooksFile();
    final content = await Storage.readWithRecovery(file);
    if (content != null) {
      try {
        final data = jsonDecode(content);
        notebooks = (data as List)
            .map((e) => Notebook.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        CrashLog.log('notebooks 解析失败: $e');
        notebooks = [];
      }
    } else {
      notebooks = [];
    }
    notifyListeners();
  }

  Notebook createNotebook(String name, int gradientIndex) {
    final nb = Notebook(
      id: _newId('nb'),
      name: name,
      gradientIndex: gradientIndex,
      createdAt: DateTime.now().toIso8601String(),
    );
    notebooks.insert(0, nb);
    save();
    notifyListeners();
    return nb;
  }

  void deleteNotebook(String id) {
    notebooks.removeWhere((n) => n.id == id);
    save();
    notifyListeners();
  }

  void renameNotebook(String id, String name, {int? gradientIndex}) {
    final nb = notebook(id);
    nb.name = name;
    if (gradientIndex != null) nb.gradientIndex = gradientIndex;
    save();
    notifyListeners();
  }

  Notebook notebook(String id) {
    if (notebooks.isEmpty) {
      return Notebook(id: 'empty', name: '空', gradientIndex: 0, createdAt: '');
    }
    return notebooks.firstWhere(
      (n) => n.id == id,
      orElse: () => notebooks.first,
    );
  }

  Source addSource(
    Notebook nb, {
    required String name,
    required String text,
    required String type,
    String? filePath,
  }) {
    final src = Source(
      id: _newId('src'),
      name: name,
      type: type,
      rawText: text,
      filePath: filePath,
      createdAt: DateTime.now().toIso8601String(),
      chunks: Chunker.chunkText(text, sourceName: name),
    );
    nb.sources.insert(0, src);
    save();
    notifyListeners();
    return src;
  }

  void removeSource(Notebook nb, String id) {
    nb.sources.removeWhere((s) => s.id == id);
    save();
    notifyListeners();
  }

  /// 错题去重：同题干只保留一条（刷新作答时间与快照）
  void addMistake(Notebook nb, Question q) {
    final text = q.question.trim();
    final idx = nb.mistakes.indexWhere(
        (m) => m.question.question.trim() == text);
    if (idx != -1) {
      nb.mistakes[idx].questionJson = jsonEncode(q.toJson());
      nb.mistakes[idx].answeredAt = DateTime.now().toIso8601String();
    } else {
      nb.mistakes.insert(
        0,
        Mistake(
          questionId: q.id,
          questionJson: jsonEncode(q.toJson()),
          answeredAt: DateTime.now().toIso8601String(),
        ),
      );
    }
    save();
  }

  /// 串行写入队列：避免高频率改动时并发写同一文件导致损坏
  void save() {
    _writeQueue = _writeQueue.then((_) => _doSave());
  }

  Future<void> _doSave() async {
    try {
      final file = await Storage.notebooksFile();
      await Storage.writeAtomic(
        file,
        jsonEncode(notebooks.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      CrashLog.log('保存失败: $e');
    }
  }

  static String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
