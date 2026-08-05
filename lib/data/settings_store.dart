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
  }
}
