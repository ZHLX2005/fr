import 'package:flutter_quill/flutter_quill.dart' as quill;

/// Markdown 格式化操作类
///
/// 提供 Wolai 风格的底部 MD 按钮功能
/// 内部映射到富文本格式 Attribute（体验像 Markdown，内部不必严格 Markdown）
class MdActions {
  final quill.QuillController controller;
  final void Function() onFormat;

  MdActions({
    required this.controller,
    required this.onFormat,
  });

  /// 切换粗体
  void toggleBold() {
    final isOn = _getSelectionStyle()
        .attributes
        .containsKey(quill.Attribute.bold.key);
    _format(isOn
        ? quill.Attribute.clone(quill.Attribute.bold, null)
        : quill.Attribute.bold);
  }

  /// 切换斜体
  void toggleItalic() {
    final isOn = _getSelectionStyle()
        .attributes
        .containsKey(quill.Attribute.italic.key);
    _format(isOn
        ? quill.Attribute.clone(quill.Attribute.italic, null)
        : quill.Attribute.italic);
  }

  /// 切换行内代码
  void toggleInlineCode() {
    final isOn = _getSelectionStyle()
        .attributes
        .containsKey(quill.Attribute.inlineCode.key);
    _format(isOn
        ? quill.Attribute.clone(quill.Attribute.inlineCode, null)
        : quill.Attribute.inlineCode);
  }

  /// 设置标题级别
  ///
  /// [level] - 标题级别 (1-6)，0 表示普通文本
  void setHeader(int level) {
    if (level == 0) {
      _format(quill.Attribute.clone(quill.Attribute.header, null));
    } else {
      _format(quill.HeaderAttribute(level: level));
    }
  }

  /// 切换引用块
  void toggleQuoteBlock() {
    final attrs = _getSelectionStyle().attributes;
    final isQuote = attrs.containsKey(quill.Attribute.blockQuote.key);
    _format(isQuote
        ? quill.Attribute.clone(quill.Attribute.blockQuote, null)
        : quill.Attribute.blockQuote);
  }

  /// 切换项目列表
  void toggleBulletList() {
    final attrs = _getSelectionStyle().attributes;
    final isList = attrs[quill.Attribute.list.key]?.value == quill.Attribute.ul.value;
    _format(isList
        ? quill.Attribute.clone(quill.Attribute.list, null)
        : quill.Attribute.ul);
  }

  /// 切换数字列表
  void toggleOrderedList() {
    final attrs = _getSelectionStyle().attributes;
    final isList = attrs[quill.Attribute.list.key]?.value == quill.Attribute.ol.value;
    _format(isList
        ? quill.Attribute.clone(quill.Attribute.list, null)
        : quill.Attribute.ol);
  }

  /// 获取当前选区的样式
  quill.Style _getSelectionStyle() {
    return controller.getSelectionStyle();
  }

  /// 应用格式并触发回调
  void _format(quill.Attribute attribute) {
    controller.formatSelection(attribute);
    onFormat();
  }
}

/// Markdown 格式化操作的按钮定义
class MdButtonDef {
  /// 按钮文本
  final String label;

  /// 按钮提示
  final String? tooltip;

  /// 点击回调
  final void Function() onTap;

  /// 是否为切换按钮（有点击高亮状态）
  final bool isToggle;

  const MdButtonDef({
    required this.label,
    this.tooltip,
    required this.onTap,
    this.isToggle = true,
  });
}

/// 预定义的 Markdown 按钮列表
List<MdButtonDef> createMdButtons(MdActions actions) {
  return [
    MdButtonDef(
      label: 'B',
      tooltip: '粗体',
      onTap: actions.toggleBold,
    ),
    MdButtonDef(
      label: 'I',
      tooltip: '斜体',
      onTap: actions.toggleItalic,
    ),
    MdButtonDef(
      label: '</>',
      tooltip: '行内代码',
      onTap: actions.toggleInlineCode,
    ),
    MdButtonDef(
      label: 'H1',
      tooltip: '一级标题',
      onTap: () => actions.setHeader(1),
    ),
    MdButtonDef(
      label: 'H2',
      tooltip: '二级标题',
      onTap: () => actions.setHeader(2),
    ),
    MdButtonDef(
      label: 'H3',
      tooltip: '三级标题',
      onTap: () => actions.setHeader(3),
    ),
    MdButtonDef(
      label: '"""',
      tooltip: '引用',
      onTap: actions.toggleQuoteBlock,
    ),
    MdButtonDef(
      label: '•',
      tooltip: '无序列表',
      onTap: actions.toggleBulletList,
    ),
    MdButtonDef(
      label: '1.',
      tooltip: '有序列表',
      onTap: actions.toggleOrderedList,
    ),
  ];
}
