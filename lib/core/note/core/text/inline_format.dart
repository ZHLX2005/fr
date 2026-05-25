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

  /// 工厂注册表。type → 反序列化工厂，与 [part] 指令一一对应。
  static final Map<String, InlineFormatFactory> _registry = {
    'bold': (_) => const BoldFormat(),
    'italic': (_) => const ItalicFormat(),
    'inline_code': (_) => const InlineCodeFormat(),
    'strikethrough': (_) => const StrikethroughFormat(),
    'link': (d) => LinkFormat(d['url'] as String? ?? ''),
    'mention': (d) => MentionFormat(d['block_id'] as String? ?? ''),
    'color': (d) => ColorFormat(d['color'] as String? ?? ''),
  };

  factory InlineFormat.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    final factory = _registry[type];
    if (factory == null) {
      throw ArgumentError('Unknown inline format type: "$type".');
    }
    return factory(json);
  }
}

/// 内联格式反序列化工厂类型。
typedef InlineFormatFactory = InlineFormat Function(Map<String, dynamic> json);
