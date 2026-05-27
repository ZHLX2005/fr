import 'type.dart';
import 'type_conversion_rule.dart';

/// 输入类型转换注册表 — 接收规则列表，提供 tryConvert。
class TypeConversionRegistry {
  final List<TypeConversionRule<BlockType>> _rules;

  TypeConversionRegistry(this._rules);

  /// 若 [text] 开头匹配某规则，返回 (目标类型, 转换后内容)，否则 null。
  (BlockType type, String rest)? tryConvert(String text) {
    for (final rule in _rules) {
      final match = rule.pattern.matchAsPrefix(text);
      if (match == null) continue;
      final type = rule.createType(match);
      final rest = rule.clearContent ? '' : text.substring(match.end);
      return (type, rest);
    }
    return null;
  }

  /// 从各类型静态 inputTrigger/inputTriggers 构建默认注册表。
  static TypeConversionRegistry createDefault() => TypeConversionRegistry([
    DividerType.inputTrigger,
    CodeType.inputTrigger,
    ...HeadingType.inputTriggers,
    BulletListItemType.inputTrigger,
    OrderedListItemType.inputTrigger,
    TodoType.inputTrigger,
    QuoteType.inputTrigger,
  ]);
}
