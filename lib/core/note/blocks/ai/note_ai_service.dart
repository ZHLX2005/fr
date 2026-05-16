import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../models/ai_chat_message.dart' show AISettings;

/// AI 工具调用信息
class ToolCallInfo {
  final String id;
  final String type;
  final String name;
  final String arguments;

  const ToolCallInfo({
    required this.id,
    required this.type,
    required this.name,
    required this.arguments,
  });

  Map<String, dynamic> toAssistantMessageMap() => {
        'id': id,
        'type': type,
        'function': {
          'name': name,
          'arguments': arguments,
        },
      };
}

/// AI 对话服务
///
/// 直接调用 LLM API（OpenAI 兼容格式），不经过后端代理。
/// 支持工具调用（tool_use），用于 AI 操作 BlockTree。
class NoteAiService {
  String _apiKey = '';
  String _baseUrl = '';
  String _model = '';

  bool get isConfigured => _apiKey.isNotEmpty;

  /// 从 AISettings 更新配置
  void updateFromSettings(AISettings settings) {
    _apiKey = settings.apiKey;
    _baseUrl = settings.baseURL;
    _model = settings.model;
  }

  /// 清空配置
  void clearConfig() {
    _apiKey = '';
    _baseUrl = '';
    _model = '';
  }

  /// 发送对话消息，返回 AI 回复 + 工具调用
  /// [messages] 是用户/助手/工具消息历史（不含 system 消息）。
  Future<AiConversationResult> chat({
    required List<Map<String, dynamic>> messages,
    required String systemPrompt,
    List<Map<String, dynamic>>? tools,
  }) async {
    if (_apiKey.isEmpty) {
      return AiConversationResult(error: '请先在侧边栏 → 设置中配置 API Key');
    }

    final url = _buildUrl();
    if (url == null) {
      return AiConversationResult(error: '请正确配置 API URL');
    }

    try {
      final body = <String, dynamic>{
        'model': _model.isNotEmpty ? _model : 'glm-4v-flash',
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          ...messages,
        ],
        'stream': false,
        'temperature': 0.3,
      };

      if (tools != null && tools.isNotEmpty) {
        body['tools'] = tools;
        body['tool_choice'] = 'auto';
      }

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode != 200) {
        final errorBody = _tryExtractError(response.body);
        return AiConversationResult(
          error: 'API 返回错误 (${response.statusCode}): $errorBody',
        );
      }

      return _parseResponse(response.body);
    } catch (e) {
      return AiConversationResult(error: '请求失败: $e');
    }
  }

  // ──────────── 内部 ────────────

  Uri? _buildUrl() {
    final url = _baseUrl.isNotEmpty ? _baseUrl : 'https://open.bigmodel.cn/api/paas/v4/chat/completions';
    return Uri.tryParse(url);
  }

  String _tryExtractError(String body) {
    try {
      final json = jsonDecode(body);
      return json['error']?['message']?.toString() ?? json['error']?.toString() ?? body;
    } catch (_) {
      return body.length > 200 ? '${body.substring(0, 200)}...' : body;
    }
  }

  AiConversationResult _parseResponse(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        return AiConversationResult(error: 'API 返回空响应');
      }

      final message = choices[0]['message'] as Map<String, dynamic>?;
      if (message == null) {
        return AiConversationResult(error: 'API 返回格式异常');
      }

      final reply = message['content'] as String? ?? '';
      final toolCallsRaw = message['tool_calls'] as List<dynamic>?;

      final toolCalls = <ToolCallInfo>[];
      if (toolCallsRaw != null) {
        for (final tc in toolCallsRaw) {
          final tcMap = tc as Map<String, dynamic>;
          final function = tcMap['function'] as Map<String, dynamic>?;
          if (function != null) {
            toolCalls.add(ToolCallInfo(
              id: tcMap['id'] as String? ?? '',
              type: tcMap['type'] as String? ?? 'function',
              name: function['name'] as String? ?? '',
              arguments: function['arguments'] as String? ?? '{}',
            ));
          }
        }
      }

      return AiConversationResult(reply: reply, toolCalls: toolCalls);
    } catch (e) {
      return AiConversationResult(error: '解析响应失败: $e');
    }
  }
}

/// AI 对话响应
class AiConversationResult {
  final String reply;
  final List<ToolCallInfo> toolCalls;
  final String? error;

  bool get isError => error != null && error!.isNotEmpty;
  bool get hasToolCalls => toolCalls.isNotEmpty;

  const AiConversationResult({
    this.reply = '',
    this.toolCalls = const [],
    this.error,
  });
}
