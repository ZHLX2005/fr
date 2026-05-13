import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../const_note_theme.dart';
import '../embed/embed_card_builder.dart';
import '../services/ai_service.dart';
import 'md_actions.dart';
import 'space_ai_trigger.dart';
import 'md_priority_input.dart';

/// 笔记编辑器页面
///
/// 仿 wolai/息流/Notion 的编辑原型
class NoteEditorPage extends StatefulWidget {
  final AiService? aiService;
  final String? initialContent;
  final String? title;

  const NoteEditorPage({
    super.key,
    this.aiService,
    this.initialContent,
    this.title,
  });

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final QuillController _controller;
  final FocusNode _editorFocus = FocusNode();

  // AI 输入框
  final TextEditingController _aiInputController = TextEditingController();
  bool _aiBarVisible = false;

  // MD 优先输入控制器
  late final MarkdownPriorityInputController _mdCtrl;

  // 新行空格唤醒 AI 触发器
  late final NewLineSpaceAiBarTrigger _aiTrigger;

  late final MdActions _mdActions;

  @override
  void initState() {
    super.initState();

    final initialText = widget.initialContent ??
        'MD 优先输入：行首输入 # 空格、- 空格、> 空格 试试。\n'
            '新行行首输入一个空格唤醒 AI 输入框。\n';

    _controller = QuillController(
      document: Document()..insert(0, initialText),
      selection: const TextSelection.collapsed(offset: 0),
    );

    _mdActions = MdActions(
      controller: _controller,
      onFormat: () => _editorFocus.requestFocus(),
    );

    // 启动 MD 优先输入
    _mdCtrl = MarkdownPriorityInputController(controller: _controller)..start();

    // 启动 AI 触发器
    _aiTrigger = NewLineSpaceAiBarTrigger(
      controller: _controller,
      onShowAiBar: _showAiBar,
    )..start();
  }

  @override
  void dispose() {
    _mdCtrl.dispose();
    _aiTrigger.dispose();
    _controller.dispose();
    _editorFocus.dispose();
    _aiInputController.dispose();
    super.dispose();
  }

  void _showAiBar() {
    setState(() => _aiBarVisible = true);
  }

  void _hideAiBar() {
    setState(() => _aiBarVisible = false);
    _aiInputController.clear();
    _editorFocus.requestFocus();
  }

  void _commitAiCommand() {
    final cmd = _aiInputController.text.trim();
    if (cmd.isEmpty) {
      _hideAiBar();
      return;
    }
    _insertTextAtCursor('ai:$cmd\n');
    _hideAiBar();
  }

  /// 在光标位置插入文本
  void _insertTextAtCursor(String text) {
    final sel = _controller.selection;
    final index = sel.baseOffset < 0 ? 0 : sel.baseOffset;

    if (!sel.isCollapsed) {
      _controller.document.delete(sel.start, sel.end - sel.start);
    }
    _controller.document.insert(index, text);
    _controller.updateSelection(
      TextSelection.collapsed(offset: index + text.length),
      ChangeSource.local,
    );
  }

  /// 插入嵌入卡片
  void _insertEmbedCard() {
    final sel = _controller.selection;
    final index = sel.baseOffset < 0 ? 0 : sel.baseOffset;

    final data = EmbedCardData(
      title: '嵌入块（原型）',
      subtitle: '这里可以代表：页面引用/附件/数据库卡片/Markdown块 等',
      icon: 'page',
    );

    final embed = BlockEmbed.custom(
      CustomBlockEmbed(EmbedTypes.card, data.toPayload()),
    );

    _controller.document.insert(index, embed);
    _controller.updateSelection(
      TextSelection.collapsed(offset: index + 1),
      ChangeSource.local,
    );

    _editorFocus.requestFocus();
  }

  /// 插入分割线
  void _insertDivider() {
    _insertTextAtCursor('\n---\n');
  }

  @override
  Widget build(BuildContext context) {
    final mdButtons = createMdButtons(_mdActions);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ?? '笔记编辑器',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF242424) : const Color(0xFFFAFAFA),
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: Container(
        color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF),
        child: Column(
          children: [
            Expanded(
              child: QuillEditor.basic(
                controller: _controller,
                config: QuillEditorConfig(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  autoFocus: true,
                  expands: false,
                  embedBuilders: [
                    EmbedCardBuilder(),
                  ],
                  customStyles: _getEditorStyles(isDark),
                ),
              ),
            ),

            // AI 输入框（被空格唤醒）
            if (_aiBarVisible) _buildAiInputBar(),

            // 底部功能栏
            _buildBottomBar(mdButtons),
          ],
        ),
      ),
    );
  }

  /// 获取编辑器自定义样式
  DefaultStyles _getEditorStyles(bool isDark) {
    final colors = NoteEditorTheme.getColors(isDark ? Brightness.dark : Brightness.light);

    return DefaultStyles(
      h1: DefaultTextBlockStyle(
        TextStyle(
          fontSize: NoteEditorTheme.h1FontSize,
          fontWeight: FontWeight.bold,
          color: colors.h1,
          height: 1.3,
        ),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(16, 8),
        const VerticalSpacing(0, 0),
        null,
      ),
      h2: DefaultTextBlockStyle(
        TextStyle(
          fontSize: NoteEditorTheme.h2FontSize,
          fontWeight: FontWeight.bold,
          color: colors.h2,
          height: 1.3,
        ),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(14, 6),
        const VerticalSpacing(0, 0),
        null,
      ),
      h3: DefaultTextBlockStyle(
        TextStyle(
          fontSize: NoteEditorTheme.h3FontSize,
          fontWeight: FontWeight.w600,
          color: colors.h3,
          height: 1.3,
        ),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(12, 4),
        const VerticalSpacing(0, 0),
        null,
      ),
      h4: DefaultTextBlockStyle(
        TextStyle(
          fontSize: NoteEditorTheme.h4FontSize,
          fontWeight: FontWeight.w600,
          color: colors.h4,
          height: 1.3,
        ),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(10, 4),
        const VerticalSpacing(0, 0),
        null,
      ),
      h5: DefaultTextBlockStyle(
        TextStyle(
          fontSize: NoteEditorTheme.h5FontSize,
          fontWeight: FontWeight.w500,
          color: colors.h5,
          height: 1.3,
        ),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(8, 4),
        const VerticalSpacing(0, 0),
        null,
      ),
      h6: DefaultTextBlockStyle(
        TextStyle(
          fontSize: NoteEditorTheme.h6FontSize,
          fontWeight: FontWeight.w500,
          color: colors.h6,
          height: 1.3,
        ),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(6, 4),
        const VerticalSpacing(0, 0),
        null,
      ),
      paragraph: DefaultTextBlockStyle(
        TextStyle(
          fontSize: 15,
          color: colors.onSurface,
          height: 1.6,
        ),
        const HorizontalSpacing(0, 0),
        const VerticalSpacing(6, 6),
        const VerticalSpacing(0, 0),
        null,
      ),
    );
  }

  Widget _buildAiInputBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final aiColor = isDark ? const Color(0xFFFFCA28) : const Color(0xFFFFD54F);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFFFF8E1),
          border: Border(
            top: BorderSide(
              color: aiColor.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, color: aiColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _aiInputController,
                autofocus: true,
                style: TextStyle(
                  color: isDark ? const Color(0xFFE0E0E0) : const Color(0xFF2D2D2D),
                ),
                decoration: InputDecoration(
                  hintText: '输入命令，回车提交，例如：总结上文',
                  hintStyle: TextStyle(
                    color: isDark ? const Color(0xFF757575) : const Color(0xFF9E9E9E),
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onSubmitted: (_) => _commitAiCommand(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _commitAiCommand,
              icon: Icon(Icons.send_rounded, color: aiColor),
              tooltip: '发送',
            ),
            IconButton(
              onPressed: _hideAiBar,
              icon: Icon(
                Icons.close,
                color: isDark ? const Color(0xFF9E9E9E) : const Color(0xFF757575),
              ),
              tooltip: '关闭',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(List<MdButtonDef> mdButtons) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFFAFAFA),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF3D3D3D) : const Color(0xFFE0E0E0),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              // AI 按钮
              _buildToolbarButton(
                icon: Icons.auto_awesome,
                tooltip: 'AI 助手',
                onPressed: _aiBarVisible ? null : _showAiBar,
                isHighlight: true,
                highlightColor: isDark ? const Color(0xFFFFCA28) : const Color(0xFFFFD54F),
              ),

              const SizedBox(width: 8),
              _buildDivider(isDark),
              const SizedBox(width: 8),

              // Markdown 格式按钮组
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...mdButtons.map((btn) => Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: _buildToolbarButton(
                              icon: btn.icon,
                              label: btn.label,
                              tooltip: btn.tooltip ?? '',
                              onPressed: btn.onTap,
                            ),
                          )),

                      const SizedBox(width: 8),
                      _buildDivider(isDark),
                      const SizedBox(width: 8),

                      // 嵌入卡片按钮
                      _buildToolbarButton(
                        icon: Icons.add_box_outlined,
                        tooltip: '嵌入卡片',
                        onPressed: _insertEmbedCard,
                      ),

                      // 分割线按钮
                      _buildToolbarButton(
                        icon: Icons.horizontal_rule,
                        tooltip: '分割线',
                        onPressed: _insertDivider,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbarButton({
    IconData? icon,
    String? label,
    required String tooltip,
    required VoidCallback? onPressed,
    bool isHighlight = false,
    Color? highlightColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final defaultColor = isDark ? const Color(0xFF9E9E9E) : const Color(0xFF757575);
    final activeColor = isHighlight
        ? (highlightColor ?? defaultColor)
        : (isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2));

    if (icon != null) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPressed,
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(
                icon,
                size: 22,
                color: onPressed == null
                    ? defaultColor.withValues(alpha: 0.4)
                    : activeColor,
              ),
            ),
          ),
        ),
      );
    }

    // 文字按钮（备选）
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label ?? '',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: onPressed == null
                ? defaultColor.withValues(alpha: 0.4)
                : activeColor,
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Container(
      width: 1,
      height: 24,
      color: isDark ? const Color(0xFF3D3D3D) : const Color(0xFFE0E0E0),
    );
  }
}
