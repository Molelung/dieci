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
