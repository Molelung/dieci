import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../data/settings_store.dart';

class AiMessage {
  final String role; // user | model
  final String text;

  const AiMessage(this.role, this.text);
}

/// Gemini REST 客户端（generativelanguage.googleapis.com v1beta）
/// 官方 Dart SDK 已弃用，直连 REST + SSE 流式，支持 responseSchema 强约束。
class GeminiClient {
  final SettingsStore settings;
  final Dio _dio;

  GeminiClient(this.settings)
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 120),
          headers: {'Content-Type': 'application/json'},
        ));

  String get _base => settings.baseUrl.replaceAll(RegExp(r'/$'), '');

  bool get hasKey => settings.apiKey.isNotEmpty;

  Map<String, dynamic> _body({
    required List<AiMessage> contents,
    String? system,
    Map<String, dynamic>? generationConfig,
  }) {
    return {
      'contents': contents
          .map((c) => {'role': c.role, 'parts': [{'text': c.text}]})
          .toList(),
      if (system != null) 'systemInstruction': {'parts': [{'text': system}]},
      if (generationConfig != null) 'generationConfig': generationConfig,
    };
  }

  /// 流式生成，逐段吐出文本增量
  Stream<String> streamGenerate({
    required List<AiMessage> contents,
    String? system,
    double? temperature,
    int maxTokens = 8192,
    Map<String, dynamic>? responseSchema,
    List<String>? stopSequences,
  }) async* {
    if (!hasKey) {
      throw Exception('未配置 API Key，请先到「设置」填写 Gemini API Key');
    }

    final generationConfig = <String, dynamic>{
      'temperature': temperature ?? settings.temperature,
      'maxOutputTokens': maxTokens,
      if (stopSequences != null && stopSequences.isNotEmpty)
        'stopSequences': stopSequences,
      if (responseSchema != null) ...{
        'responseMimeType': 'application/json',
        'responseSchema': responseSchema,
      },
    };

    final url =
        '$_base/models/${settings.model}:streamGenerateContent?alt=sse';
    final body = _body(
      contents: contents,
      system: system,
      generationConfig: generationConfig,
    );

    try {
      final response = await _dio.post<ResponseBody>(
        url,
        data: jsonEncode(body),
        options: Options(
          responseType: ResponseType.stream,
          headers: {'x-goog-api-key': settings.apiKey},
        ),
      );

      final stream = utf8
          .decoder
          .bind(response.data!.stream)
          .transform(const LineSplitter());

      await for (final line in stream) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;
        final payload = trimmed.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;

        final dynamic json;
        try {
          json = jsonDecode(payload);
        } catch (_) {
          continue;
        }

        if (json is Map<String, dynamic> && json['error'] != null) {
          final err = json['error'];
          throw Exception(_errorText(err));
        }

        final text = _extractText(json);
        if (text != null && text.isNotEmpty) yield text;
      }
    } on DioException catch (e) {
      throw Exception(_dioError(e));
    }
  }

  /// 非流式一次拿完整文本（用于简单测试）
  Future<String> generateOnce({
    required List<AiMessage> contents,
    String? system,
    double? temperature,
  }) async {
    final sb = StringBuffer();
    await for (final c in streamGenerate(
      contents: contents,
      system: system,
      temperature: temperature,
      maxTokens: 1024,
    )) {
      sb.write(c);
    }
    return sb.toString();
  }

  /// 拉取当前 Key 可见的 Gemini 模型列表（`GET /v1beta/models`）
  /// 结果按「Pro/推理 → Flash → Flash-Lite」排序，供设置页挑选。
  Future<List<String>> listModels() async {
    if (!hasKey) return const [];
    try {
      final res = await _dio.get<dynamic>(
        '$_base/models',
        options: Options(headers: {'x-goog-api-key': settings.apiKey}),
      );
      final data = res.data;
      if (data is! Map || data['models'] is! List) return const [];
      final names = <String>[];
      for (final m in data['models'] as List) {
        if (m is! Map) continue;
        final name = m['name']?.toString();
        if (name == null || !name.startsWith('models/gemini-')) continue;
        final short = name.substring('models/'.length);
        if (short.contains('image') ||
            short.contains('embedding') ||
            short.contains('audio') ||
            short.contains('nano')) {
          continue;
        }
        names.add(short);
      }
      _sortByPriority(names);
      return names;
    } on DioException {
      return const [];
    }
  }

  /// 探测某个模型是否可用，返回 (模型, 是否成功, 提示)
  Future<(String, bool, String)> probeModel(String model) async {
    try {
      await generateOnce(
        contents: [const AiMessage('user', '只回复两个字：OK')],
        temperature: 0,
      );
      return (model, true, '可用');
    } catch (e) {
      return (model, false, e.toString());
    }
  }

  /// 探测 Pro 订阅：依次探测 pro 系模型，返回可用的 Pro 模型列表
  Future<List<String>> detectProModels() async {
    const candidates = [
      'gemini-3.1-pro-preview',
      'gemini-3-pro-preview',
      'gemini-3-flash-preview',
      'gemini-3.6-flash',
      'gemini-2.5-flash',
    ];
    final ok = <String>[];
    for (final m in candidates) {
      try {
        await generateOnce(
          contents: [const AiMessage('user', 'OK')],
          temperature: 0,
        );
        ok.add(m);
      } catch (_) {
        // 探测失败继续下一个
      }
    }
    return ok;
  }

  static void _sortByPriority(List<String> names) {
    int rank(String n) {
      if (n.contains('pro-preview') || n.contains('pro-exp')) return 0;
      if (n.contains('pro')) return 1;
      if (n.contains('deep-think')) return 2;
      if (n.contains('flash-preview')) return 3;
      if (n.contains('flash-lite')) return 4;
      if (n.contains('flash')) return 5;
      return 6;
    }

    names.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return b.compareTo(a);
    });
  }

  String? _extractText(dynamic json) {
    try {
      final candidates = json['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;
      final parts = candidates[0]['content']?['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;
      final text = parts[0]['text'] as String?;
      return text;
    } catch (_) {
      return null;
    }
  }

  String _errorText(dynamic err) {
    if (err is Map) {
      final message = err['message'];
      if (message is String) return message;
    }
    return 'Gemini API 返回错误';
  }

  String _dioError(DioException e) {
    final code = e.response?.statusCode;
    final body = e.response?.data;
    if (body != null) {
      try {
        final map = jsonDecode(body.toString());
        final msg = map['error']?['message'];
        if (msg is String) return '$msg (HTTP $code)';
      } catch (_) {}
    }
    switch (code) {
      case 400:
        return '请求格式错误 (HTTP 400)，请检查 Base URL 与模型名';
      case 401:
        return 'API Key 无效 (HTTP 401)，请检查设置';
      case 403:
        return 'API Key 无权限访问该模型 (HTTP 403)，可能需要订阅或更换模型';
      case 404:
        return '模型不存在 (HTTP 404)：${settings.model}';
      case 429:
        return '触发速率限制 (HTTP 429)，稍后再试，或升级订阅档位';
      default:
        return '网络请求失败：$code ${e.message ?? ''}';
    }
  }
}
