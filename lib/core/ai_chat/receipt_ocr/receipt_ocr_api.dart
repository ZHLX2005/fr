import '../../../api/api_client.dart';
import '../../../api/api_config.dart';
import '../../../api/api_response.dart';
import '../../../api/goframe/ai/ai_endpoint.dart';
import '../../../api/token/token_storage.dart';
import '../../../api/token/token_manager.dart';
import '../../../services/ai_chat/ai_chat_models.dart';
import 'receipt_ocr_models.dart';

/// 小票 OCR —— 调后端 flex 接口（`template: receipt_ocr`）识别小票图片。
///
/// apiKey/model/baseURL/type 来自 [AISettings]（与 ai_chat_settings_page 共享
/// 同一份 LLM 配置，不重复存储）。flex 接口自带 apiKey 鉴权，无需 JWT。
class ReceiptOcrApi {
  final AiEndpoint _ai;

  ReceiptOcrApi() : _ai = AiEndpoint(_defaultClient());

  static ApiClient _defaultClient() {
    return ApiClient(
      config: ApiConfig.production(),
      tokenManager: TokenManager(storage: SharedPrefsTokenStorage()),
    );
  }

  /// 识别一张小票图片。[imageBase64] 形如 `data:image/jpeg;base64,...`。
  /// 解析失败或接口报错时抛异常，调用方负责 SnackBar 提示。
  Future<ReceiptResult> recognize({
    required AISettings settings,
    required String imageBase64,
  }) async {
    final ApiResponse<FlexChatResponse> res = await _ai.flexChat(
      apiKey: settings.apiKey,
      model: settings.model.isNotEmpty ? settings.model : null,
      baseUrl: settings.baseURL.isNotEmpty ? settings.baseURL : null,
      type: settings.type.isNotEmpty ? settings.type : null,
      template: 'receipt_ocr',
      prompt: '识别这张小票。',
      images: [
        {'base64': imageBase64, 'detail': 'high'},
      ],
      maxTokens: 1024,
    );

    if (!res.isSuccess || res.data == null) {
      throw Exception('flex 接口失败: ${res.message} (code=${res.code})');
    }
    return ReceiptResult.fromFlexContent(res.data!.content);
  }
}