import 'receipt_ocr_models.dart';

/// 小票 OCR 假后端。
/// 等待 800ms 返回硬编码数据，模拟 LLM 识别延迟。
/// 真后端接入时把 recognize() 改成 http 调用即可。
class ReceiptOcrApi {
  static Future<ReceiptResult> recognize() async {
    await Future.delayed(const Duration(milliseconds: 800));
    return ReceiptResult(
      storeName: '盒马鲜生',
      purchasedAt: DateTime.now(),
      recommendedTopic: '日常水果',
      items: const [
        LineItem(resource: '红富士苹果', quantity: 2, unitPrice: 5.5, note: '盒马'),
        LineItem(resource: '进口香蕉',   quantity: 1, unitPrice: 12.8, note: '盒马'),
        LineItem(resource: '泰国椰青',   quantity: 3, unitPrice: 9.9, note: '盒马'),
        LineItem(resource: '巨峰葡萄',   quantity: 1, unitPrice: 28.0, note: '盒马'),
        LineItem(resource: '云南蓝莓',   quantity: 2, unitPrice: 19.9, note: '盒马'),
      ],
    );
  }
}