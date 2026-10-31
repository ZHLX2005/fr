import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 单张图片的 AI 分析结果。
///
/// [fields] 保存 AI 返回的**完整 JSON**（详情页完全由它驱动）；
/// 以下是列表页消费的「标准字段」——AI 按提示词契约输出，缺失时走兜底。
@immutable
class AiScanResult {
  /// 对应 AssetEntity.id（photo_manager），作为持久化主键。
  final String assetId;

  /// AI 推断的标题。
  final String title;

  /// AI 推断的一句话描述。
  final String description;

  /// 分组名（截图/照片/文档/…）。
  final String group;

  /// AI 返回的完整 JSON（含 tags、importance 及所有额外字段）。
  final Map<String, dynamic> fields;

  /// 扫描时间。
  final DateTime scannedAt;

  const AiScanResult({
    required this.assetId,
    required this.title,
    required this.description,
    required this.group,
    required this.fields,
    required this.scannedAt,
  });

  /// 标签列表（fields['tags']，兜底空）。
  List<String> get tags {
    final raw = fields['tags'];
    if (raw is! List) return const [];
    return [for (final t in raw) if (t is String) t];
  }

  /// AI 推断的重要性 → 是否高亮。
  bool get isImportant {
    final v = fields['importance'];
    return v is String && v.toLowerCase() == 'high';
  }

  /// 列表页不直接显示的标准字段 + tags + importance 之外的全部字段
  /// （详情页动态渲染区用）。
  Map<String, dynamic> get extraFields {
    const reserved = {'title', 'description', 'group', 'tags', 'importance'};
    return {
      for (final e in fields.entries)
        if (!reserved.contains(e.key)) e.key: e.value,
    };
  }

  factory AiScanResult.fromAiJson({
    required String assetId,
    required Map<String, dynamic> fields,
  }) {
    return AiScanResult(
      assetId: assetId,
      title: (fields['title'] as String?)?.trim().isNotEmpty == true
          ? (fields['title'] as String).trim()
          : '未命名',
      description: fields['description'] as String? ?? '',
      group: (fields['group'] as String?)?.trim().isNotEmpty == true
          ? (fields['group'] as String).trim()
          : '其他',
      fields: fields,
      scannedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'assetId': assetId,
    'fields': fields,
    'scannedAt': scannedAt.millisecondsSinceEpoch,
  };

  factory AiScanResult.fromJson(Map<String, dynamic> json) {
    final fields =
        (json['fields'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return AiScanResult(
      assetId: json['assetId'] as String? ?? '',
      title: fields['title'] as String? ?? '未命名',
      description: fields['description'] as String? ?? '',
      group: fields['group'] as String? ?? '其他',
      fields: fields,
      scannedAt: DateTime.fromMillisecondsSinceEpoch(
        json['scannedAt'] as int? ?? 0,
      ),
    );
  }
}

/// JSON 解析失败：[detail] 是给人和模型都能看懂的「错误日志」，
/// [rawReply] 保留模型原始回复 —— 重试提示词要靠它告诉模型错在哪。
class AiGalleryParseException extends FormatException {
  final String detail;
  final String rawReply;

  AiGalleryParseException(this.detail, {required this.rawReply}) : super(detail);

  @override
  String toString() => 'AiGalleryParseException: $detail';
}

/// 把异常压成一行可读文本（日志、网格错误态、重试提示词三处共用）。
String describeAiError(Object error) {
  if (error is AiGalleryParseException) return error.detail;
  if (error is FormatException) return error.message;
  return error.toString();
}

/// 把 AI 回复文本解析成 JSON [Map]。
///
/// 容忍模型不听话的三种常见形态：
/// 1. 纯 JSON；
/// 2. 裹在 ```json ... ``` 代码块里（receipt_ocr 同款 strip 逻辑）；
/// 3. JSON 前后有解释文字（取第一个 `{` 到最后一个 `}`）。
/// 解析失败抛 [AiGalleryParseException]（FormatException 子类），
/// 异常里带够定位的错误描述，可直接当重试提示词里的错误回执。
Map<String, dynamic> parseAiJson(String content) {
  final raw = content;
  var text = content.trim();
  if (text.isEmpty) {
    throw AiGalleryParseException('AI 回复为空（0 字）', rawReply: raw);
  }
  // strip ```json ... ``` 代码块
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
  final m = fence.firstMatch(text);
  if (m != null) text = m.group(1)!.trim();
  // 截取首尾大括号
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw AiGalleryParseException(
      '回复里找不到完整的 JSON 对象（缺少 { 或 }，全文 ${raw.length} 字）',
      rawReply: raw,
    );
  }
  final slice = text.substring(start, end + 1);
  final Object? decoded;
  try {
    decoded = jsonDecode(slice);
  } on FormatException catch (e) {
    final at = e.offset == null ? '' : '（第 ${e.offset} 个字符附近）';
    throw AiGalleryParseException(
      'JSON 语法错误：${e.message}$at',
      rawReply: raw,
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw AiGalleryParseException(
      '顶层不是 JSON 对象（实际是 ${decoded.runtimeType}）',
      rawReply: raw,
    );
  }
  return decoded;
}
