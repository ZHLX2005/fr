import 'inline_format_registry.dart';
import 'rich_text.dart';
import 'span.dart';

/// RichText ↔ JSON 互转编解码器。依赖 [InlineFormatRegistry] 反序列化内联格式。
class RichTextCodec {
  final InlineFormatRegistry _formatRegistry;

  RichTextCodec(this._formatRegistry);

  Map<String, dynamic> encode(RichText text) => text.toJson();

  RichText decode(Map<String, dynamic> json) {
    final list = json['spans'] as List<dynamic>?;
    if (list == null || list.isEmpty) return RichText.empty();
    return RichText(list.map((s) => _decodeSpan(s as Map<String, dynamic>)).toList());
  }

  Span _decodeSpan(Map<String, dynamic> json) {
    final formatJson = json['format'] as Map<String, dynamic>?;
    return Span(
      json['text'] as String? ?? '',
      format: formatJson != null
          ? _formatRegistry.resolve(
              formatJson['type'] as String? ?? '',
              Map<String, dynamic>.from(formatJson),
            )
          : null,
    );
  }
}
