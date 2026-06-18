import 'package:flutter/foundation.dart';
import '../../../../api/api_response.dart';
import '../../../../api/goframe/ai/ai_endpoint.dart';
import 'ai_settings_store.dart';

/// 调用后端 ai/chat 的函数签名（= AiEndpoint.chat 的 tear-off 类型）。
typedef AiChatCall = Future<ApiResponse<ChatResponse>> Function({
  required String apiKey,
  required String prompt,
  String? model,
  String? baseUrl,
  String? type,
});

/// 封装 ai/chat 的业务调用。
///
/// 与 [ArticleEditService] 并列：article/edit 用于全文编辑（一次改文 + diff），
/// ai/chat 用于多轮闲聊（纯文本回复，无 diff，无文章修改）。
class AiChatService {
  final AiChatCall _chatCall;

  AiChatService({required AiChatCall chatCall}) : _chatCall = chatCall;

  factory AiChatService.forEndpoint(AiEndpoint endpoint) {
    return AiChatService(chatCall: endpoint.chat);
  }

  /// 发送单轮对话。返回 AI 回复文本。
  ///
  /// 失败抛 [AiChatException]，调用方应捕获并显示。
  Future<String> chat({
    required String prompt,
    required AiSettings settings,
  }) async {
    if (!settings.isConfigured) {
      throw AiChatException('请先在设置中配置 API Key');
    }
    debugPrint('[AiChat] sending POST /api/v1/ai/chat prompt="$prompt"');
    final resp = await _chatCall(
      apiKey: settings.apiKey,
      prompt: prompt,
      model: settings.model.isEmpty ? null : settings.model,
      baseUrl: settings.baseUrl.isEmpty ? null : settings.baseUrl,
      type: 'claude',
    );
    debugPrint('[AiChat] response: success=${resp.isSuccess} code=${resp.code} msg="${resp.message}" content.len=${resp.data?.content.length ?? 0}');

    if (!resp.isSuccess || resp.data == null) {
      throw AiChatException(resp.message.isEmpty ? '请求失败' : resp.message);
    }
    return resp.data!.content;
  }
}

class AiChatException implements Exception {
  final String message;
  AiChatException(this.message);
  @override
  String toString() => 'AiChatException: $message';
}
