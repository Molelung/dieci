import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  SettingsStore._();
  static final SettingsStore i = SettingsStore._();

  static const _defaultBaseUrl = 'https://generativelanguage.googleapis.com/v1beta';
  static const _defaultModel = 'gemini-2.5-flash';

  String apiKey = '';
  String baseUrl = _defaultBaseUrl;
  String model = _defaultModel;
  double temperature = 0.3;
  String lastVaultPath = '';
  List<String> quizTypes = ['single', 'tf'];
  int quizCount = 10;
  String quizDifficulty = '中等';
  bool quizMistakeFirst = false;

  static const modelSuggestions = [
    'gemini-2.5-flash',
    'gemini-3-flash-preview',
    'gemini-3.5-flash',
    'gemini-3.6-flash',
    'gemini-3-pro-preview',
    'gemini-3.1-pro-preview',
  ];

  static const _storage = FlutterSecureStorage();

  Future<void> load() async {
    try {
      apiKey = await _storage.read(key: 'gemini_api_key') ?? '';
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString('base_url') ?? _defaultBaseUrl;
    model = prefs.getString('model') ?? _defaultModel;
    temperature = prefs.getDouble('temperature') ?? 0.3;
    lastVaultPath = prefs.getString('last_vault_path') ?? '';
    quizTypes = prefs.getStringList('quiz_types') ?? ['single', 'tf'];
    quizCount = prefs.getInt('quiz_count') ?? 10;
    quizDifficulty = prefs.getString('quiz_difficulty') ?? '中等';
    quizMistakeFirst = prefs.getBool('quiz_mistake_first') ?? false;
  }

  Future<void> save() async {
    if (apiKey.isNotEmpty) {
      await _storage.write(key: 'gemini_api_key', value: apiKey);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('base_url', baseUrl);
    await prefs.setString('model', model);
    await prefs.setDouble('temperature', temperature);
    await prefs.setString('last_vault_path', lastVaultPath);
    await prefs.setStringList('quiz_types', quizTypes);
    await prefs.setInt('quiz_count', quizCount);
    await prefs.setString('quiz_difficulty', quizDifficulty);
    await prefs.setBool('quiz_mistake_first', quizMistakeFirst);
  }
}
