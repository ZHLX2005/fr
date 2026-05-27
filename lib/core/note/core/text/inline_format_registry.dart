import 'inline_format.dart';

/// 内联格式反序列化工厂类型。
typedef InlineFormatFactory = InlineFormat Function(Map<String, dynamic> json);

/// 内联格式反序列化注册表。构造时接收完整工厂 Map。
class InlineFormatRegistry {
  final Map<String, InlineFormatFactory> _factories;

  InlineFormatRegistry(this._factories);

  InlineFormat resolve(String tag, [Map<String, dynamic> data = const {}]) {
    final factory = _factories[tag];
    if (factory == null) {
      throw ArgumentError('Unknown inline format type: "$tag".');
    }
    return factory(data);
  }
}

/// 全部 7 种 InlineFormat 的工厂 Map 构造器。
class InlineFormatRegistrar {
  const InlineFormatRegistrar();

  Map<String, InlineFormatFactory> createFactories() => {
    'bold': (_) => const BoldFormat(),
    'italic': (_) => const ItalicFormat(),
    'inline_code': (_) => const InlineCodeFormat(),
    'strikethrough': (_) => const StrikethroughFormat(),
    'link': (d) => LinkFormat(d['url'] as String? ?? ''),
    'mention': (d) => MentionFormat(d['block_id'] as String? ?? ''),
    'color': (d) => ColorFormat(d['color'] as String? ?? ''),
  };
}
