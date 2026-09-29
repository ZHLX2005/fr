import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../pi_config.dart';
import '../pi_exception.dart';
import 'pi_sse_event.dart';

/// 新建会话的返回。
class PiSessionCreated {
  /// pi 侧真实 sessionId（后续所有命令都用它）。
  final String sessionId;

  /// 该会话当前使用的模型；服务端未配模型时为 `unknown/unknown`。
  final String? provider;
  final String? modelId;

  /// 思考档位（off/minimal/low/medium/high/xhigh/max）。
  final String? thinkingLevel;

  const PiSessionCreated({
    required this.sessionId,
    this.provider,
    this.modelId,
    this.thinkingLevel,
  });

  /// 服务端是否真的解析到了模型（false 时 prompt 会报 No API key found）。
  bool get hasRealModel =>
      modelId != null && modelId!.isNotEmpty && modelId != 'unknown';

  factory PiSessionCreated.fromJson(Map<String, dynamic> json) {
    final model = json['model'];
    return PiSessionCreated(
      sessionId: (json['sessionId'] ?? '').toString(),
      provider: model is Map ? model['provider']?.toString() : null,
      modelId: model is Map ? model['modelId']?.toString() : null,
      thinkingLevel: json['thinkingLevel']?.toString(),
    );
  }

  @override
  String toString() {
    final model = '${provider ?? '?'}/${modelId ?? '?'}';
    return 'PiSessionCreated($sessionId, $model)';
  }
}

/// pi agent 端点：新建会话、发命令、流式事件。
///
/// 不走统一拦截器链（baseUrl 与主后端不同），自持 [http.Client]。
/// 通道与鉴权见 [PiConfig] 文档。
class PiAgentEndpoint {
  final PiConfig Function() _config;
  final http.Client _client;

  PiAgentEndpoint({required PiConfig Function() config, http.Client? client})
      : _config = config,
        _client = client ?? http.Client();

  Map<String, String> _headers() => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (_config().token.isNotEmpty)
          'Authorization': 'Bearer ${_config().token}',
      };

  /// 新建会话。
  ///
  /// [type] 传 `ensure_session` 时**只建运行时、不触发模型**（不耗额度），
  /// 适合「先进会话页再说话」的交互；传 `prompt` 则同一次请求里直接发首条消息。
  Future<PiSessionCreated> newSession({
    required String cwd,
    String type = 'ensure_session',
    String? provider,
    String? modelId,
    String? thinkingLevel,
    List<String>? toolNames,
    String? message,
  }) async {
    // 注：这里刻意用 `if (x != null)` 而不是 `'k': ?x`。后者虽是更新的字面量
    // 语法，但 build_runner（codegen）用的解析器还不认它，会让整轮 build 失败
    //（项目里 body_record 等多个模型依赖 build_runner）。忽略对应的 lint 提示。
    final body = <String, dynamic>{
      'cwd': cwd,
      'type': type,
      // ignore: use_null_aware_elements
      if (message != null) 'message': message,
      if (provider != null && modelId != null) ...{
        // ignore: use_null_aware_elements
        'provider': provider,
        'modelId': modelId,
      },
      // ignore: use_null_aware_elements
      if (thinkingLevel != null) 'thinkingLevel': thinkingLevel,
      // ignore: use_null_aware_elements
      if (toolNames != null) 'toolNames': toolNames,
    };
    final json = await _postJson('/agent/new', body, timeout: const Duration(seconds: 180));
    return PiSessionCreated.fromJson(json);
  }

  /// 发一条 prompt（返回被受理即成功；正文从 [events] 流里来）。
  Future<void> prompt(String sessionId, String message, {List<Object>? images}) =>
      command(sessionId, {
        'type': 'prompt',
        'message': message,
        if (images != null && images.isNotEmpty) 'images': images,
      });

  /// 通用命令通道。返回网关响应里的 `data`（可能为 null）。
  ///
  /// 常用 type：`get_state` / `get_tools` / `get_commands` / `get_session_stats` /
  /// `get_last_assistant_text` / `abort` / `set_model` / `set_thinking_level` /
  /// `set_session_name` / `compact` / `steer` / `follow_up`。
  Future<dynamic> command(
    String sessionId,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final json = await _postJson('/agent/$sessionId', body, timeout: timeout);
    return json['data'];
  }

  /// 便捷：本轮助手文本。
  Future<String> lastAssistantText(String sessionId) async {
    final data = await command(sessionId, {'type': 'get_last_assistant_text'});
    return (data is Map ? data['text']?.toString() : null) ?? '';
  }

  /// 便捷：会话状态（isStreaming / model / thinkingLevel 等）。
  Future<Map<String, dynamic>> state(String sessionId) async {
    final data = await command(sessionId, {'type': 'get_state'});
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  /// 便捷：中止当前运行。
  Future<void> abort(String sessionId) =>
      command(sessionId, {'type': 'abort'}, timeout: const Duration(seconds: 90));

  /// 便捷：切换思考档位。
  Future<void> setThinkingLevel(String sessionId, String level) =>
      command(sessionId, {'type': 'set_thinking_level', 'level': level});

  /// 事件流（SSE）。
  ///
  /// **必须带 Authorization 头** —— 这是手机端最稳的方式（nx-as 的短票通道
  /// 线上不可用）。用 [http.Client.send] 拿到流后按行解析 `data:` 帧。
  /// 调用方取消订阅即断开连接。
  Stream<PiSseEvent> events(String sessionId) {
    final cfg = _config();
    final uri = cfg.uri('/agent/$sessionId/events');
    late StreamController<PiSseEvent> controller;
    http.Client? streamClient;

    Future<void> start() async {
      try {
        streamClient = http.Client();
        final req = http.Request('GET', uri)
          ..headers.addAll({
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
            if (cfg.token.isNotEmpty) 'Authorization': 'Bearer ${cfg.token}',
          });
        final resp = await streamClient!.send(req);
        if (resp.statusCode != 200) {
          final body = await resp.stream.bytesToString();
          controller.addError(
            PiApiException.fromResponse(resp.statusCode, body),
          );
          await controller.close();
          return;
        }
        final buffer = StringBuffer();
        await for (final chunk in resp.stream.transform(utf8.decoder)) {
          buffer.write(chunk);
          // SSE 以空行分帧；逐帧取出并解析
          var text = buffer.toString();
          var idx = text.indexOf('\n\n');
          while (idx >= 0) {
            final frame = text.substring(0, idx);
            text = text.substring(idx + 2);
            final evt = _parseFrame(frame);
            if (evt != null && !controller.isClosed) controller.add(evt);
            idx = text.indexOf('\n\n');
          }
          buffer
            ..clear()
            ..write(text);
        }
        if (!controller.isClosed) await controller.close();
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(
            e is PiApiException
                ? e
                : PiApiException(statusCode: 0, message: '$e'),
          );
          await controller.close();
        }
      }
    }

    controller = StreamController<PiSseEvent>(
      onListen: start,
      onCancel: () async {
        streamClient?.close();
      },
    );
    return controller.stream;
  }

  /// 解析一帧：把若干 `data:` 行拼起来（pi-web 只发 data 行）。
  PiSseEvent? _parseFrame(String frame) {
    final buf = StringBuffer();
    for (final line in frame.split('\n')) {
      if (line.startsWith('data:')) {
        var payload = line.substring(5);
        if (payload.startsWith(' ')) payload = payload.substring(1);
        buf.write(payload);
      }
    }
    if (buf.isEmpty) return null;
    try {
      return PiSseEvent.fromJson(json.decode(buf.toString()));
    } catch (_) {
      return null;
    }
  }

  /// POST 并解析 `{success, data, error}` 外壳。
  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body, {
    required Duration timeout,
  }) async {
    final cfg = _config();
    if (!cfg.isConfigured) {
      throw const PiApiException(
        statusCode: 0,
        message: 'pi 未配置：请先在设置里填写服务地址与 device token',
        code: 'NOT_CONFIGURED',
      );
    }
    http.Response resp;
    try {
      resp = await _client
          .post(cfg.uri(path), headers: _headers(), body: json.encode(body))
          .timeout(timeout);
    } on TimeoutException {
      throw PiApiException(
        statusCode: 0,
        message: '请求超时（${timeout.inSeconds}s）：$path',
        code: 'TIMEOUT',
      );
    } catch (e) {
      throw PiApiException(statusCode: 0, message: '$e', code: 'NETWORK');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw PiApiException.fromResponse(resp.statusCode, resp.body);
    }
    final decoded = json.decode(utf8.decode(resp.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw PiApiException(
        statusCode: resp.statusCode,
        message: '响应不是 JSON 对象: ${resp.body}',
      );
    }
    // pi-web 的错误可能以 200 返回（如 prompt_rejected 的 404/500 会带 code）
    final err = decoded['error'];
    if (err != null && decoded['success'] != true) {
      throw PiApiException.fromResponse(resp.statusCode, resp.body);
    }
    return decoded;
  }

  void close() => _client.close();
}
