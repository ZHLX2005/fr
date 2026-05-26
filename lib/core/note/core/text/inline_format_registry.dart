import 'inline_format.dart';

/// 内联格式反序列化工厂类型。
typedef InlineFormatFactory = InlineFormat Function(Map<String, dynamic> json);

/// 内联格式反序列化注册表。按 tag 查找对应工厂。
class InlineFormatRegistry {
  final Map<String, InlineFormatFactory> _factories = {};

  void register(String tag, InlineFormatFactory factory) {
    _factories[tag] = factory;
  }

  InlineFormat resolve(String tag, [Map<String, dynamic> data = const {}]) {
    final factory = _factories[tag];
    if (factory == null) {
      throw ArgumentError('Unknown inline format type: "$tag".');
    }
    return factory(data);
  }
}

/// 注册全部 7 种 InlineFormat。与 [inline_format.dart] 的 [part] 指令一一对应。
class InlineFormatRegistrar {
  const InlineFormatRegistrar();

  void registerAll(InlineFormatRegistry registry) {
    registry.register('bold', (_) => const BoldFormat());
    registry.register('italic', (_) => const ItalicFormat());
    registry.register('inline_code', (_) => const InlineCodeFormat());
    registry.register('strikethrough', (_) => const StrikethroughFormat());
    registry.register('link', (d) => LinkFormat(d['url'] as String? ?? ''));
    registry.register('mention', (d) => MentionFormat(d['block_id'] as String? ?? ''));
    registry.register('color', (d) => ColorFormat(d['color'] as String? ?? ''));
  }
}
