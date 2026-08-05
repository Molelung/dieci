import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../data/settings_store.dart';
import '../utils/crash_log.dart';

class AiMessage {
  final String role; // user | model
  final String text;

  const AiMessage(this.role, this.text);
}

/// Gemini REST 客户端（generativelanguage.googleapis.com v1beta）
/// 稳定性设计：
/// - SSE 行缓冲：半包/心跳/多行 data 容错，坏事件自愈不拖垮会话
/// - finishReason 全覆盖：STOP 才算成功；MAX_TOKENS/SAFETY/RECITATION 转友好错误
/// - 仅对 408/429/5xx 做指数退避重试（尊重 Retry-After）
/// - 每请求 CancelToken，页面销毁可立即中断
class GeminiClient {
  final SettingsStore settings;
  final Dio _dio;

  GeminiClient(this.settings)
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          // SSE 长流不做按字节超时，改由应用层/重试兜底
          receiveTimeout: null,
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

  /// 流式生成，逐段吐出文本增量。
  /// 瞬时错误自动指数退避重试（最多 3 次）。
  Stream<String> streamGenerate({
    required List<AiMessage> contents,
    String? system,
    double? temperature,
    int maxTokens = 8192,
    Map<String, dynamic>? responseSchema,
    List<String>? stopSequences,
    CancelToken? cancelToken,
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

    final url = '$_base/models/${settings.model}:streamGenerateContent?alt=sse';
    final body = _body(
      contents: contents,
      system: system,
      generationConfig: generationConfig,
    );

    const maxAttempts = 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        yield* _streamOnce(url, body, cancelToken);
        return;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          throw Exception('已取消');
        }
        final code = e.response?.statusCode;
        final retryable =
            code == 408 || code == 429 || (code != null && code >= 500);
        if (retryable && attempt < maxAttempts - 1) {
          final retryAfter = _retryAfter(e.response?.headers);
          final delay = retryAfter ??
              Duration(seconds: 1 << attempt) +
                  Duration(milliseconds: 100 + (attempt * 137) % 400);
          CrashLog.log('Gemini 瞬时错误 HTTP $code，第 ${attempt + 2} 次尝试');
          await Future.delayed(delay);
          continue;
        }
        throw Exception(_dioError(e));
      }
    }
  }

  Stream<String> _streamOnce(
      String url, Map<String, dynamic> body, CancelToken? cancelToken) async* {
    final response = await _dio.post<ResponseBody>(
      url,
      data: jsonEncode(body),
      options: Options(
        responseType: ResponseType.stream,
        headers: {'x-goog-api-key': settings.apiKey},
      ),
      cancelToken: cancelToken,
    );

    final stream = utf8
        .decoder
        .bind(response.data!.stream)
        .transform(const LineSplitter());

    final payload = <String>[];
    String? lastFinishReason;
    var sawText = false;

    // 局部函数不可 yield，改为返回本次事件解析出的文本片段列表
    List<String> flush() {
      if (payload.isEmpty) return const [];
      final raw = payload.join('\n');
      payload.clear();
      if (raw.isEmpty || raw == '[DONE]') return const [];

      final dynamic json;
      try {
        json = jsonDecode(raw);
      } catch (_) {
        return const []; // 半包自愈：跳过坏事件继续读流
      }
      if (json is! Map<String, dynamic>) return const [];

      if (json['error'] != null) {
        throw Exception(_errorText(json['error']));
      }

      final pf = json['promptFeedback'];
      if (pf is Map && pf['blockReason'] != null) {
        throw Exception('内容被安全策略拦截（${pf['blockReason']}），请检查材料或调整提示词');
      }

      final text = _extractText(json);
      if (text != null && text.isNotEmpty) sawText = true;

      final cands = json['candidates'];
      if (cands is List && cands.isNotEmpty && cands[0] is Map) {
        final fr = cands[0]['finishReason'];
        if (fr is String) lastFinishReason = fr;
      }
      return text == null ? const [] : [text];
    }

    try {
      await for (final line in stream) {
        if (cancelToken?.isCancelled ?? false) {
          throw DioException.connectionError(
            requestOptions: RequestOptions(path: url),
            reason: '已取消',
          );
        }
        final t = line.trim();
        if (t.isEmpty) {
          for (final x in flush()) {
            yield x;
          }
          continue;
        }
        if (t.startsWith(':')) continue; // 心跳注释
        if (t.startsWith('data:')) payload.add(t.substring(5).trim());
      }
      for (final x in flush()) {
        yield x;
      }

      switch (lastFinishReason) {
        case 'MAX_TOKENS':
          throw Exception('输出达到 token 上限被截断，请减少题量或增加输出限制后重试');
        case 'SAFETY':
          throw Exception('生成内容被安全过滤，请调整提示词后重试');
        case 'RECITATION':
          throw Exception('生成内容疑似大段照抄，请精简材料后重试');
        case null:
          if (!sawText) throw Exception('流式响应为空或连接中断，请重试');
      }
    } on DioException {
      rethrow;
    } catch (e) {
      // flush() 内抛出的业务异常直接上抛
      rethrow;
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

  /// 探测某个模型是否可用
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

  /// 依次探测候选模型，返回可用的（Pro 优先）
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
      } catch (_) {}
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

  Duration? _retryAfter(Headers? headers) {
    if (headers == null) return null;
    final v = headers.value('retry-after');
    if (v == null || v.isEmpty) return null;
    final seconds = int.tryParse(v);
    if (seconds != null) return Duration(seconds: seconds.clamp(1, 60));
    final date = DateTime.tryParse(v);
    if (date != null) {
      final diff = date.difference(DateTime.now());
      if (diff.inSeconds > 0 && diff.inSeconds <= 60) return diff;
    }
    return null;
  }

  String? _extractText(dynamic json) {
    try {
      final candidates = json['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;
      final parts = candidates[0]['content']?['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;
      return parts[0]['text'] as String?;
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
    if (CancelToken.isCancel(e)) return '请求已取消';
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
        return '触发速率限制 (HTTP 429)，请稍后再试，或升级订阅档位';
      default:
        return '网络请求失败：$code ${e.message ?? ''}';
    }
  }
}
