import 'package:get_it/get_it.dart';

import '../../../services/message_strategy/data/data.dart';
import '../../../services/message_strategy/panel/panel.dart';
import 'receipt_ocr_api.dart';

/// 调假后端 → 装成 ReceiptOcrMessageData → 喂到全局面板。
class ReceiptOcrRouter {
  static final MessagePanelController _panel =
      GetIt.instance<MessagePanelController>();

  /// 调假后端识别一次，结果 append 到面板。
  /// 返回值是数据本身，方便调用方做后续处理（如报错 SnackBar）。
  static Future<ReceiptOcrMessageData?> runOnce() async {
    try {
      final result = await ReceiptOcrApi.recognize();
      final data = ReceiptOcrMessageData(result: result);
      _panel.append(data);
      return data;
    } catch (_) {
      return null;
    }
  }
}