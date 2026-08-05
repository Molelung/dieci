import 'dart:io';
import 'package:path_provider/path_provider.dart';

class Storage {
  Storage._();

  static Directory? _dir;

  static Future<Directory> dir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    _dir = Directory('${base.path}${Platform.pathSeparator}dieci_data');
    await _dir!.create(recursive: true);
    return _dir!;
  }

  static Future<File> notebooksFile() async {
    final d = await dir();
    return File('${d.path}${Platform.pathSeparator}notebooks.json');
  }
}
