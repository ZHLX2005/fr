import '../../../core/ai_chat/receipt_ocr/receipt_ocr_models.dart';
import '../interfaces/message_data.dart';

/// 小票 OCR 识别结果消息。
class ReceiptOcrMessageData implements IMessageData {
  final ReceiptResult result;

  ReceiptOcrMessageData({required this.result});

  @override
  String get type => 'receipt_ocr';
}
