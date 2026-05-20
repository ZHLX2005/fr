import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart' show LogicalKeyboardKey, SingleActivator;
import '../block.dart';
import '../block_type.dart';
import 'markdown_text_controller.dart';

/// Block → Widget 渲染器
///
/// 根据 BlockType 渲染对应的 Widget，可编辑类型使用 TextField。
class BlockWidget extends StatefulWidget {
  final Block block;
  final bool isSelected;
  final ValueChanged<String>? onTap;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onDeleteEmpty;
  final FocusNode? focusNode;

  const BlockWidget({
    super.key,
    required this.block,
    this.isSelected = false,
    this.onTap,
    this.onSubmitted,
    this.onChanged,
    this.onDeleteEmpty,
    this.focusNode,
  });

  @override
  State<BlockWidget> createState() => _BlockWidgetState();
}

class _BlockWidgetState extends State<BlockWidget> {
  late MarkdownTextController _textController;

  @override
  void initState() {
    super.initState();
    _textController = MarkdownTextController(text: widget.block.content.toPlainText());
  }

  @override
  void didUpdateWidget(BlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // block id 变了 → 完全切换块，直接同步
    if (oldWidget.block.id != widget.block.id) {
      _textController.text = widget.block.content.toPlainText();
      return;
    }
    // 同一块，内容从外部改变时（撤销/重做/快捷键转换）同步 TextField
    if (oldWidget.block.content != widget.block.content) {
      final newText = widget.block.content.toPlainText();
      if (_textController.text != newText) {
        _textController.text = newText;
        _textController.selection = TextSelection.collapsed(offset: newText.length);
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _isEditable => switch (widget.block.type) {
        BlockType.page || BlockType.divider || BlockType.image ||
        BlockType.embedCard || BlockType.database || BlockType.bookmark ||
        BlockType.equation || BlockType.syncedBlock => false,
        _ => true,
      };

  void _onTextChanged(String value) {
    widget.onChanged?.call(value);
  }

  void _onSubmit() {
    final text = _textController.text;
    if (text.isNotEmpty) {
      widget.onSubmitted?.call(text);
    }
  }

  void _insertNewline() {
    final text = _textController.text;
    final sel = _textController.selection;
    final offset = sel.isValid && sel.isCollapsed ? sel.baseOffset : text.length;
    final newText = '${text.substring(0, offset)}\n${text.substring(offset)}';
    _textController.text = newText;
    _textController.selection = TextSelection.collapsed(offset: offset + 1);
  }

  /// Enter → 提交（新建块），Shift+Enter → 换行
  Widget _wrapEnterHandling(Widget child) {
    return Shortcuts(
      shortcuts: {
        SingleActivator(LogicalKeyboardKey.enter): _SubmitIntent(),
        SingleActivator(LogicalKeyboardKey.enter, shift: true): _NewlineIntent(),
      },
      child: Actions(
        actions: {
          _SubmitIntent: CallbackAction<_SubmitIntent>(onInvoke: (_) {
            _onSubmit();
            return null;
          }),
          _NewlineIntent: CallbackAction<_NewlineIntent>(onInvoke: (_) {
            _insertNewline();
            return null;
          }),
        },
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        widget.onTap?.call(widget.block.id);
        // 选中时自动聚焦编辑框
        if (_isEditable && widget.isSelected) {
          FocusScope.of(context).requestFocus(widget.focusNode);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: widget.isSelected
              ? (isDark ? Colors.blue.withValues(alpha: 0.08) : Colors.blue.withValues(alpha: 0.05))
              : null,
          border: widget.isSelected
              ? Border(
                  left: BorderSide(
                    color: isDark ? Colors.blue.shade300 : Colors.blue,
                    width: 3,
                  ),
                )
              : null,
        ),
        padding: EdgeInsets.only(
          left: 16 + (widget.isSelected ? 0 : 3),
          right: 16,
          top: 4,
          bottom: 4,
        ),
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return switch (widget.block.type) {
      BlockType.page              => _buildPage(context),
      BlockType.heading            => _buildHeading(context),
      BlockType.paragraph          => _buildParagraph(context),
      BlockType.todo               => _buildTodo(context),
      BlockType.toggle             => _buildToggle(context),
      BlockType.bulletListItem     => _buildBulletList(context),
      BlockType.orderedListItem    => _buildOrderedList(context),
      BlockType.quote              => _buildQuote(context),
      BlockType.code               => _buildCode(context),
      BlockType.divider            => _buildDivider(context),
      BlockType.callout            => _buildCallout(context),
      BlockType.image              => _buildImage(context),
      BlockType.embedCard          => _buildEmbedCard(context),
      BlockType.database           => _buildDatabase(context),
      BlockType.bookmark           => _buildParagraph(context),
      BlockType.equation           => _buildEquation(context),
      BlockType.columnList => _buildParagraph(context),
      BlockType.column => _buildParagraph(context),
      BlockType.syncedBlock => _buildParagraph(context),
    };
  }

  // ─── 通用可编辑文本字段 ───

  Widget _editableText({
    required String text,
    double fontSize = 15,
    FontWeight fontWeight = FontWeight.normal,
    double height = 1.6,
    String? fontFamily,
    TextAlign textAlign = TextAlign.start,
  }) {
    return _wrapEnterHandling(
      TextField(
        controller: _textController,
        focusNode: widget.focusNode,
        textAlign: textAlign,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.send,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontFamily: fontFamily,
          height: height,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
          hintText: _hintText(),
          hintStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25),
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontFamily: fontFamily,
          ),
        ),
        onChanged: _onTextChanged,
        onSubmitted: (_) => _onSubmit(),
      ),
    );
  }

  String _hintText() {
    return switch (widget.block.type) {
      BlockType.heading    => '标题',
      BlockType.todo       => '待办事项',
      BlockType.quote      => '引用',
      BlockType.code       => '代码',
      BlockType.callout    => '提示',
      _                    => '输入文字...',
    };
  }

  // ─── 只读文本 ───

  Widget _readOnlyText(String text, {double fontSize = 15, FontWeight fontWeight = FontWeight.normal, double height = 1.6}) {
    if (text.isEmpty) return const SizedBox(height: 24);
    return Text(
      text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  // ─── 各类型构建 ───

  Widget _buildPage(BuildContext context) {
    return _readOnlyText(
      widget.block.content.toPlainText(),
      fontSize: 24,
      fontWeight: FontWeight.bold,
    );
  }

  Widget _buildHeading(BuildContext context) {
    final level = widget.block.data.get<int>('level') ?? 1;
    final sizes = [28, 22, 18, 16, 15, 14];
    final size = level >= 1 && level <= 6 ? sizes[level - 1] : 18;
    return _editableText(
      text: widget.block.content.toPlainText(),
      fontSize: size.toDouble(),
      fontWeight: level <= 2 ? FontWeight.bold : FontWeight.w600,
      height: 1.3,
    );
  }

  Widget _buildParagraph(BuildContext context) {
    return _editableText(
      text: widget.block.content.toPlainText(),
      fontSize: 15,
      height: 1.6,
    );
  }

  Widget _buildTodo(BuildContext context) {
    final checked = widget.block.data.get<bool>('checked') ?? false;
    return Row(
      children: [
        Icon(
          checked ? Icons.check_box : Icons.check_box_outline_blank,
          size: 20,
          color: checked
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _wrapEnterHandling(
            TextField(
              controller: _textController,
              focusNode: widget.focusNode,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.send,
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                decoration: checked ? TextDecoration.lineThrough : null,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: '待办事项',
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25),
                ),
              ),
              onChanged: _onTextChanged,
              onSubmitted: (_) => _onSubmit(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggle(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.arrow_right, size: 18),
        const SizedBox(width: 8),
        Expanded(child: _editableText(
          text: widget.block.content.toPlainText(),
          height: 1.6,
        )),
      ],
    );
  }

  Widget _buildBulletList(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, right: 8),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        Expanded(child: _editableText(
          text: widget.block.content.toPlainText(),
          height: 1.6,
        )),
      ],
    );
  }

  Widget _buildOrderedList(BuildContext context) {
    final number = widget.block.data.get<int>('number') ?? 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Text(
            '$number.',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _editableText(
          text: widget.block.content.toPlainText(),
          height: 1.6,
        )),
      ],
    );
  }

  Widget _buildQuote(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
            width: 3,
          ),
        ),
      ),
      child: _wrapEnterHandling(
        TextField(
          controller: _textController,
          focusNode: widget.focusNode,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.send,
          style: TextStyle(
            fontSize: 15,
            fontStyle: FontStyle.italic,
            height: 1.6,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
            hintText: '引用',
            hintStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25),
              fontStyle: FontStyle.italic,
            ),
          ),
          onChanged: _onTextChanged,
          onSubmitted: (_) => _onSubmit(),
        ),
      ),
    );
  }

  Widget _buildCode(BuildContext context) {
    final language = widget.block.data.get<String>('language') ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (language.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                language,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          _wrapEnterHandling(
            TextField(
              controller: _textController,
              focusNode: widget.focusNode,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.send,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                height: 1.5,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: '在此输入代码...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25),
                ),
              ),
              onChanged: _onTextChanged,
              onSubmitted: (_) => _onSubmit(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Divider(
      height: 24,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }

  Widget _buildCallout(BuildContext context) {
    final icon = widget.block.data.get<String>('icon') ?? '💡';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(child: _editableText(
            text: widget.block.content.toPlainText(),
            height: 1.6,
          )),
        ],
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    final caption = widget.block.data.get<String>('caption');
    return Column(
      children: [
        Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Icon(Icons.image_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
          ),
        ),
        if (caption != null && caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(caption,
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Widget _buildEmbedCard(BuildContext context) {
    final title = widget.block.data.get<String>('title') ?? '';
    final subtitle = widget.block.data.get<String>('subtitle') ?? '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.link, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDatabase(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.table_chart_outlined, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            widget.block.content.toPlainText().isEmpty ? '数据库' : widget.block.content.toPlainText(),
            style: const TextStyle(fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildEquation(BuildContext context) {
    final latex = widget.block.data.get<String>('latex') ?? widget.block.content.toPlainText();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        latex.isEmpty ? '\$\$ \\text{公式} \$\$' : latex,
        style: TextStyle(
          fontSize: 15,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// Enter → 提交新块（桌面物理键盘）
class _SubmitIntent extends Intent {}

/// Shift+Enter → 插入换行
class _NewlineIntent extends Intent {}
