import 'dart:convert';

import 'receipt_ocr_models.dart';

/// 单条历史识别记录。
///
/// 图片保存到 app docs 目录（`getApplicationDocumentsDirectory()/receipt_ocr/`），
/// 这里只存文件名（不是绝对路径），避免重启后路径漂移。ReceiptResult 直接复用，
/// 含 default_topic 等。
class ReceiptOcrHistory {
  final String id;
  final DateTime createdAt;
  final ReceiptResult result;
  /// app docs/receipt_ocr/ 目录下的文件名（不是绝对路径）。
  final String imageFileName;

  const ReceiptOcrHistory({
    required this.id,
    required this.createdAt,
    required this.result,
    required this.imageFileName,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'imageFileName': imageFileName,
        'result': _resultToJson(result),
      };

  factory ReceiptOcrHistory.fromJson(Map<String, dynamic> json) =>
      ReceiptOcrHistory(
        id: json['id'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        imageFileName: json['imageFileName'] as String,
        result: _resultFromJson(json['result'] as Map<String, dynamic>),
      );

  static Map<String, dynamic> _resultToJson(ReceiptResult r) => {
        'storeName': r.storeName,
        'purchasedAt': r.purchasedAt.toIso8601String(),
        'recommendedTopic': r.recommendedTopic,
        'items': r.items.map((i) => i.toJson()).toList(),
      };

  static ReceiptResult _resultFromJson(Map<String, dynamic> json) =>
      ReceiptResult(
        storeName: (json['storeName'] as String?) ?? '',
        purchasedAt:
            DateTime.tryParse((json['purchasedAt'] as String?) ?? '') ??
                DateTime.now(),
        recommendedTopic: (json['recommendedTopic'] as String?) ?? '',
        items: ((json['items'] as List?) ?? const [])
            .map((e) => LineItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static String encodeList(List<ReceiptOcrHistory> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<ReceiptOcrHistory> decodeList(String s) {
    final raw = jsonDecode(s) as List<dynamic>;
    return raw
        .map((e) => ReceiptOcrHistory.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}