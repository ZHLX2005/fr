import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? '笔记编辑器'),
      ),
      body: Column(
        children: [
          Expanded(
            child: QuillEditor.basic(
              controller: _controller,
              config: QuillEditorConfig(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                autoFocus: true,
                expands: false,
                embedBuilders: [
                  EmbedCardBuilder(),
                ],
              ),
            ),
          ),

          // AI 输入框（被空格唤醒）
          if (_aiBarVisible) _buildAiInputBar(),

          // 底部功能栏
          _buildBottomBar(mdButtons),
        ],
      ),
    );
  }

  Widget _buildAiInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(
            top: BorderSide(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.amber.shade700, size: 20),
            const SizedBox(width: 8),
            const Text(
              'AI:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _aiInputController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '输入命令，回车提交，例如：总结上文',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onSubmitted: (_) => _commitAiCommand(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _commitAiCommand,
              icon: const Icon(Icons.send),
              color: Theme.of(context).colorScheme.primary,
            ),
            IconButton(
              onPressed: _hideAiBar,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(List<MdButtonDef> mdButtons) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // AI 按钮（手动唤醒）
              FilledButton.tonal(
                onPressed: _aiBarVisible ? null : _showAiBar,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 16),
                    SizedBox(width: 6),
                    Text('AI'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(width: 1, height: 24, color: Theme.of(context).dividerColor),
              const SizedBox(width: 12),

              // Markdown 格式按钮
              ...mdButtons.map((btn) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: OutlinedButton(
                      onPressed: btn.onTap,
                      child: Text(btn.label),
                    ),
                  )),

              const SizedBox(width: 8),

              // 嵌入卡片按钮
              OutlinedButton(
                onPressed: _insertEmbedCard,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_box_outlined, size: 16),
                    SizedBox(width: 4),
                    Text('Embed'),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // 分割线按钮
              OutlinedButton(
                onPressed: _insertDivider,
                child: const Text('---'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
