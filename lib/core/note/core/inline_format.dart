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

class BoldFormat extends InlineFormat {
  const BoldFormat();
  @override
  Map<String, dynamic> toJson() => {'type': 'bold'};

  @override
  bool operator ==(Object other) => other is BoldFormat;
  @override
  int get hashCode => runtimeType.hashCode;
}

class ItalicFormat extends InlineFormat {
  const ItalicFormat();
  @override
  Map<String, dynamic> toJson() => {'type': 'italic'};

  @override
  bool operator ==(Object other) => other is ItalicFormat;
  @override
  int get hashCode => runtimeType.hashCode;
}

class InlineCodeFormat extends InlineFormat {
  const InlineCodeFormat();
  @override
  Map<String, dynamic> toJson() => {'type': 'inline_code'};

  @override
  bool operator ==(Object other) => other is InlineCodeFormat;
  @override
  int get hashCode => runtimeType.hashCode;
}

class StrikethroughFormat extends InlineFormat {
  const StrikethroughFormat();
  @override
  Map<String, dynamic> toJson() => {'type': 'strikethrough'};

  @override
  bool operator ==(Object other) => other is StrikethroughFormat;
  @override
  int get hashCode => runtimeType.hashCode;
}

class LinkFormat extends InlineFormat {
  final String url;
  const LinkFormat(this.url);

  @override
  Map<String, dynamic> toJson() => {'type': 'link', 'url': url};

  @override
  bool operator ==(Object other) => other is LinkFormat && other.url == url;
  @override
  int get hashCode => url.hashCode;
}

class MentionFormat extends InlineFormat {
  final String blockId;
  const MentionFormat(this.blockId);

  @override
  Map<String, dynamic> toJson() => {'type': 'mention', 'block_id': blockId};

  @override
  bool operator ==(Object other) =>
      other is MentionFormat && other.blockId == blockId;
  @override
  int get hashCode => blockId.hashCode;
}

class ColorFormat extends InlineFormat {
  final String color;
  const ColorFormat(this.color);

  @override
  Map<String, dynamic> toJson() => {'type': 'color', 'color': color};

  @override
  bool operator ==(Object other) =>
      other is ColorFormat && other.color == color;
  @override
  int get hashCode => color.hashCode;
}
