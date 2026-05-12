import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../embed/embed_card_builder.dart';
import '../services/ai_service.dart';
import 'md_actions.dart';
import 'space_ai_trigger.dart';

/// 笔记编辑器页面
///
/// 仿 wolai/息流/Notion 的编辑原型
class NoteEditorPage extends StatefulWidget {
  /// AI 服务配置
  final AiService? aiService;

  /// 初始文档内容
  final String? initialContent;

  /// 页面标题
  final String? title;

  const NoteEditorPage({
    super.key,
    this.aiService,
    this.initialContent,
    this.title,
  });

  @override
  State<NoteEditorPage> createState() => NoteEditorPageState();
}

class NoteEditorPageState extends State<NoteEditorPage> {
  late final QuillController _controller;
  final FocusNode _editorFocus = FocusNode();
  late final NewLineSpaceDetector _detector;
  late final AiService _ai;
  late final MdActions _mdActions;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ai = widget.aiService ?? AiService();

    final initialText = widget.initialContent ?? '新起一行，在行首输入一个空格唤醒 AI。\n';
    _controller = QuillController(
      document: Document()..insert(0, initialText),
      selection: const TextSelection.collapsed(offset: 0),
    );

    _mdActions = MdActions(
      controller: _controller,
      onFormat: () => _editorFocus.requestFocus(),
    );

    _detector = NewLineSpaceDetector(
      controller: _controller,
      onInvoke: _handleAiInvoke,
    )..start();
  }

  @override
  void dispose() {
    _detector.dispose();
    _controller.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  /// 处理 AI 唤醒
  Future<void> _handleAiInvoke(NewLineInvokeContext ctx) async {
    if (_busy) return;

    setState(() => _busy = true);
    try {
      final reply = await _ai.complete(prompt: '''
你是笔记编辑器内的 AI。
根据用户光标前的上下文，输出一段可直接插入的 Markdown（简洁、有结构）。

上下文：
${ctx.beforeCursor}
''');

      _insertTextAtCursor('\n${reply.trim()}\n');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI 生成失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _editorFocus.requestFocus();
      }
    }
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
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
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
          _buildBottomBar(mdButtons),
        ],
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
              // AI 按钮
              FilledButton.tonal(
                onPressed: _busy ? null : () => _handleAiInvoke(
                  NewLineInvokeContext(
                    beforeCursor: _controller.document.toPlainText(),
                    triggerOffset: _controller.selection.baseOffset,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_busy)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.auto_awesome, size: 16),
                    const SizedBox(width: 6),
                    const Text('AI'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 分隔线
              Container(
                width: 1,
                height: 24,
                color: Theme.of(context).dividerColor,
              ),
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
