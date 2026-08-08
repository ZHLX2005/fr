import '../../../core/ai_chat/receipt_ocr/receipt_ocr_models.dart';
import '../interfaces/message_data.dart';

/// 小票 OCR 识别结果消息。
class ReceiptOcrMessageData implements IMessageData {
  final ReceiptResult result;
  /// 关联的 OCR 历史 id（用于把行记录状态回写持久化；mock 数据为空）。
  final String? historyId;

  ReceiptOcrMessageData({required this.result, this.historyId});

  @override
  String get type => 'receipt_ocr';
}
