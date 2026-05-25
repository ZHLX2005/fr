part 'bold.dart';
part 'italic.dart';
part 'inline_code.dart';
part 'strikethrough.dart';
part 'link.dart';
part 'mention.dart';
part 'color.dart';

/// 内联格式。附着在 [Span.format] 上，描述一段文本的样式。
///
/// 每个 Span 最多带一种格式。粗体+斜体等复合格式需拆为相邻 Span。
sealed class InlineFormat {
  const InlineFormat();

  Map<String, dynamic> toJson();

  factory InlineFormat.fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String? ?? '') {
      'bold' => const BoldFormat(),
      'italic' => const ItalicFormat(),
      'inline_code' => const InlineCodeFormat(),
      'strikethrough' => const StrikethroughFormat(),
      'link' => LinkFormat(json['url'] as String? ?? ''),
      'mention' => MentionFormat(json['block_id'] as String? ?? ''),
      'color' => ColorFormat(json['color'] as String? ?? ''),
      _ => const BoldFormat(),
    };
  }
}
