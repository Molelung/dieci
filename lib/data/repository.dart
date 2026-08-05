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

  Notebook notebook(String id) =>
      notebooks.firstWhere((n) => n.id == id, orElse: () => notebooks.first);

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

  void save() async {
    final file = await Storage.notebooksFile();
    await Storage.writeAtomic(
      file,
      jsonEncode(notebooks.map((e) => e.toJson()).toList()),
    );
  }

  static String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
