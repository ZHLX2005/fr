/// 当在段落输入匹配前缀时的类型转换规则。
class TypeConversionRule<T> {
  /// 匹配开头触发的正则。
  final RegExp pattern;

  /// 根据匹配结果创建目标类型。
  final T Function(Match) createType;

  /// true 则转换后清空内容（如分割线 `---`），而非去掉前缀。
  final bool clearContent;

  const TypeConversionRule({
    required this.pattern,
    required this.createType,
    this.clearContent = false,
  });
}
