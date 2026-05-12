import 'dart:convert';
import 'package:http/http.dart' as http;

/// AI 服务层 - 支持 Mock 和 HTTP 两种模式
///
/// Mock 模式（endpoint=null）：保证原型离线可演示
/// HTTP 模式：接入 OpenAI-compatible API
class AiService {
  /// OpenAI-compatible API 端点
  /// 例如: https://api.openai.com/v1/chat/completions
  final String? endpoint;

  /// API 密钥
  final String? apiKey;

  /// 默认模型
  final String model;

  /// 生成温度 (0.0 - 1.0)
  final double temperature;

  AiService({
    this.endpoint,
    this.apiKey,
    this.model = 'gpt-4.1-mini',
    this.temperature = 0.4,
  });

  /// 完成 AI 请求
  ///
  /// [prompt] - 发送给 AI 的提示词
  /// 返回 AI 生成的文本
  Future<String> complete({required String prompt}) async {
    if (endpoint == null) {
      return _mockResponse();
    }
    return _httpRequest(prompt);
  }

  /// Mock 响应 - 保证原型离线可演示
  Future<String> _mockResponse() async {
    await Future.delayed(const Duration(milliseconds: 800));
    return [
      '## AI 输出（Mock）',
      '',
      '- 我已读取光标前上下文并生成建议。',
      '- 你可以继续输入，或用底部按钮加粗/标题/引用/列表。',
      '- 下一步可加入 `/` 命令面板来插入更多块。',
    ].join('\n');
  }

  /// HTTP 请求 - 接入真实 AI 服务
  Future<String> _httpRequest(String prompt) async {
    final resp = await http.post(
      Uri.parse(endpoint!),
      headers: {
        'Content-Type': 'application/json',
        if (apiKey != null) 'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个笔记编辑器内的 AI 助手。根据用户光标前的上下文，输出一段可直接插入的 Markdown（简洁、有结构）。'
          },
          {'role': 'user', 'content': prompt},
        ],
        'temperature': temperature,
      }),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('AI request failed: ${resp.statusCode} ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data['choices'] as List).first['message']['content'] as String;
  }
}
