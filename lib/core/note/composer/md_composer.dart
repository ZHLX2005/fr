import 'package:flutter/material.dart' hide RichText;

import '../../../design_tokens/radius.dart';
import '../../../design_tokens/spacing.dart';
import '../note_root_scope.dart';

/// **md 编辑内核**：一处写，三处装配。
///
/// ## 为什么要抽出来
///
/// nx-kv 的整条交互里有三处「用户要写一段 md」：
///
///   | 场景 | 提交到 | 需要的能力 |
///   |---|---|---|
///   | 新建任务 | `localtask.add` | 可编辑 + 预览 + 插入块 |
///   | 划线评价 | `localtask.reopen(kind=comment)` | 可编辑 + **锚定原文** + 预览 |
///   | 验收反馈 | `localtask.reopen(kind=reopen)` | 可编辑 + 模板 + 预览 |
///
/// 三处的区别只是**能力开关**，不是三个编辑器 —— 所以这里是一个壳 + 一组开关，
/// 而不是三个各自实现的弹窗（现状 `kvcli_todo_dialogs.dart` 就是三个
/// `AlertDialog + TextField`，那正是「UI 不像块编辑器」的根源）。
///
/// ## 复用的是 fr 自己的东西，不是新写一套
///
///   · 块类型清单：`noteRoot.availableTypes`（`core/note/widget/block_type_info.dart`）
///   · md → 块：`NoteFactory.parseMarkdown`
///   · 块的只读渲染：`NoteFactory.renderBlock`（`core/note/widget/` 那套策略）
///
/// 于是「预览里长什么样」与块编辑器里长什么样是**同一套渲染**，
/// 不会出现「编辑器里是引用块、预览里是一行文本」。
///
/// ## 没做的
///
/// 不做 gutter 把手、拖拽排序、AI 对话——那些是 `block_editor_demo` 的完整编辑器
/// （`EditorState`）的活。这里要的是「手机上写一段 md 并提交」，不是再造一个块编辑器。

/// 一次编辑的结果。
class MdComposerResult {
  const MdComposerResult({required this.markdown});

  final String markdown;
}

/// 打开 md 编辑器（整页，返回 null = 取消）。
Future<String?> openMdComposer(
  BuildContext context, {
  required String title,
  String hint = '支持 Markdown：# 标题、- 列表、> 引用、```代码',
  String initialText = '',
  String submitLabel = '提交',
  String? quote,
  bool showPreview = true,
  bool showInsertBlock = true,
  List<String> templates = const [],
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => MdComposerPage(
        title: title,
        hint: hint,
        initialText: initialText,
        submitLabel: submitLabel,
        quote: quote,
        showPreview: showPreview,
        showInsertBlock: showInsertBlock,
        templates: templates,
      ),
    ),
  );
}

/// md 编辑器整页。
class MdComposerPage extends StatefulWidget {
  const MdComposerPage({
    super.key,
    required this.title,
    required this.hint,
    required this.initialText,
    required this.submitLabel,
    this.quote,
    this.showPreview = true,
    this.showInsertBlock = true,
    this.templates = const [],
  });

  final String title;
  final String hint;
  final String initialText;
  final String submitLabel;

  /// 锚定原文（划线评价时给）：只读展示，提交时由调用方带进 `--quote`。
  final String? quote;

  final bool showPreview;
  final bool showInsertBlock;

  /// 模板片段（点一下插到末尾）：如「完成总结」的四段式。
  final List<String> templates;

  @override
  State<MdComposerPage> createState() => _MdComposerPageState();
}

class _MdComposerPageState extends State<MdComposerPage> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  final _focus = FocusNode();
  bool _preview = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ── 编辑操作 ──────────────────────────────────────────────

  /// 在选区两侧包标记（粗体/斜体/行内代码）；没有选区就插入一对标记并把光标放到中间。
  void _wrap(String left, String right) {
    final value = _controller.value;
    final sel = value.selection;
    final text = value.text;
    if (!sel.isValid) {
      final pos = text.length;
      _controller.value = TextEditingValue(
        text: '$text$left$right',
        selection: TextSelection.collapsed(offset: pos + left.length),
      );
      return;
    }
    final selected = sel.textInside(text);
    final next = text.replaceRange(sel.start, sel.end, '$left$selected$right');
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection(
        baseOffset: sel.start + left.length,
        extentOffset: sel.start + left.length + selected.length,
      ),
    );
    _focus.requestFocus();
  }

  /// 行首前缀（标题/列表/引用）：只作用于当前行，不破坏其它行。
  void _prefixLine(String prefix) {
    final value = _controller.value;
    final text = value.text;
    final sel = value.selection;
    final caret = sel.isValid ? sel.start : text.length;
    final lineStart = text.lastIndexOf('\n', caret == 0 ? 0 : caret - 1) + 1;
    final next = text.replaceRange(lineStart, lineStart, prefix);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret + prefix.length),
    );
    _focus.requestFocus();
  }

  void _append(String snippet) {
    final text = _controller.text;
    final needsNl = text.isNotEmpty && !text.endsWith('\n');
    _controller.text = '$text${needsNl ? '\n\n' : ''}$snippet';
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    _focus.requestFocus();
  }

  // ── 插入块 ────────────────────────────────────────────────

  /// 块清单来自 note 模块的注册表（不是这里手写一份），保证「能插的块」
  /// 与块编辑器里「能建的块」是同一份。
  Future<void> _insertBlock() async {
    final noteRoot = NoteRootScope.of(context).noteRoot;
    final types = noteRoot.availableTypes;
    final picked = await showModalBottomSheet<BlockTypeInfo>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
              child: Row(children: [
                const Text('插入块', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${types.length} 种', style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.outline)),
              ]),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final category in BlockTypeCategory.values)
                    if (types.any((t) => t.category == category)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxs),
                        child: Text(category.label,
                            style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.outline)),
                      ),
                      for (final t in types.where((t) => t.category == category))
                        ListTile(
                          dense: true,
                          leading: Icon(t.icon, size: 18),
                          title: Text(t.label, style: const TextStyle(fontSize: 13)),
                          onTap: () => Navigator.of(ctx).pop(t),
                        ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    _append(_snippetFor(picked.prototype));
  }

  /// 块类型 → md 片段。写不出来的类型返回一个空段落，不假装支持。
  String _snippetFor(BlockType type) => switch (type) {
        HeadingType() => '## ',
        BulletListItemType() => '- ',
        OrderedListItemType() => '1. ',
        TodoType() => '- [ ] ',
        QuoteType() => '> ',
        CalloutType() => '> [!NOTE] ',
        CodeType() => '```\n\n```',
        DividerType() => '\n---\n',
        EquationType() => r'$$  $$',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canSave = _controller.text.trim().isNotEmpty;

    return Scaffold(
      // 编辑页的 chrome 只留三条：44（标题栏）+ 40（工具条）+ 48（提交条）。
      // 剩下的全是输入区 —— 验收反馈要的「编辑区 80%」，在这里是硬指标：
      // 800dp 的屏上输入区 670dp ≈ 84%。原来那条 AppBar（56）+ 模板横条（44）
      // 白吃掉 100dp，写三行就要滚动。
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(cs),
            if (widget.quote != null && widget.quote!.trim().isNotEmpty) _QuoteAnchor(text: widget.quote!),
            Expanded(
              child: _preview ? _Preview(text: _controller.text) : _editor(cs),
            ),
            _toolbar(cs),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, AppSpacing.md, AppSpacing.sm),
          child: SizedBox(
            height: 40,
            child: FilledButton(
              onPressed: canSave
                  ? () => Navigator.of(context).pop(_controller.text.trim())
                  : null,
              child: Text(widget.submitLabel),
            ),
          ),
        ),
      ),
    );
  }

  /// 44dp 标题栏：关掉 / 标题 / 预览。
  ///
  /// 不用 AppBar：它在手机上固定 56dp，还要为返回箭头留 56 ——
  /// 一个「写两段 md 就要提交」的页面，标题栏不该比工具条还高。
  Widget _topBar(ColorScheme cs) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          if (widget.showPreview)
            IconButton(
              tooltip: _preview ? '回到编辑' : '预览（与块编辑器同一套渲染）',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined, color: cs.outline),
              onPressed: () => setState(() => _preview = !_preview),
            ),
        ],
      ),
    );
  }

  String _templateOf(String name) => switch (name) {
        '完成总结' => '\n## 本轮做了什么\n\n- \n\n## 怎么验的\n\n- \n\n## 遗留\n\n- 无\n',
        '验收反馈' => '\n',
        _ => '\n',
      };

  Widget _editor(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style: const TextStyle(fontSize: 14, height: 1.55),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(fontSize: 13, color: cs.outline),
          border: InputBorder.none,
          isDense: true,
        ),
        onChanged: (_) => setState(() {}), // 只为了让「提交」按钮的可用态跟上
      ),
    );
  }

  Widget _toolbar(ColorScheme cs) {
    Widget btn(IconData icon, String tip, VoidCallback onTap) => IconButton(
          tooltip: tip,
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          padding: EdgeInsets.zero,
          icon: Icon(icon, color: cs.outline),
          onPressed: onTap,
        );
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Row(
        children: [
          // 格式化按钮横向可滚：小屏放不下时不该挤成两个手指大小
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  btn(Icons.format_bold, '粗体', () => _wrap('**', '**')),
                  btn(Icons.format_italic, '斜体', () => _wrap('*', '*')),
                  btn(Icons.strikethrough_s, '删除线', () => _wrap('~~', '~~')),
                  btn(Icons.code, '行内代码', () => _wrap('`', '`')),
                  btn(Icons.title, '标题', () => _prefixLine('## ')),
                  btn(Icons.format_list_bulleted, '列表', () => _prefixLine('- ')),
                  btn(Icons.format_quote, '引用', () => _prefixLine('> ')),
                ],
              ),
            ),
          ),
          // 模板从「一整行 chip」收进菜单：那一行白占 44dp，而模板一次只用得上一个
          if (widget.templates.isNotEmpty) _templateMenu(cs),
          if (widget.showInsertBlock)
            TextButton.icon(
              onPressed: _insertBlock,
              icon: const Icon(Icons.add_box_outlined, size: 15),
              label: const Text('/', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              ),
            ),
        ],
      ),
    );
  }

  Widget _templateMenu(ColorScheme cs) {
    return PopupMenuButton<String>(
      tooltip: '插入模板',
      onSelected: (name) => _append(_templateOf(name)),
      itemBuilder: (_) => [
        for (final name in widget.templates)
          PopupMenuItem<String>(value: name, height: 38, child: Text(name, style: const TextStyle(fontSize: 12))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(
          children: [
            Icon(Icons.article_outlined, size: 15, color: cs.outline),
            const SizedBox(width: 2),
            Text('模板', style: TextStyle(fontSize: 11, color: cs.outline)),
          ],
        ),
      ),
    );
  }
}

/// 锚定原文：**只读**，告诉用户「你这句话是挂在哪段上」。
class _QuoteAnchor extends StatelessWidget {
  const _QuoteAnchor({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, 4, AppSpacing.md, 0),
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 4, AppSpacing.xs, 4),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: cs.primary, width: 2)),
        borderRadius: AppBorderRadius.allXs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('锚定原文', style: TextStyle(fontSize: 10, color: cs.outline)),
          const SizedBox(height: 1),
          // 锚定只用来提醒「挂在哪段上」，不是拿来读的：两行封顶，别把输入区往下挤
          Text(
            text.length > 200 ? '${text.substring(0, 200)}…' : text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// 预览：与块编辑器共用 `NoteFactory` 的渲染策略。
class _Preview extends StatelessWidget {
  const _Preview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final noteRoot = NoteRootScope.of(context).noteRoot;
    final blocks = noteRoot.parseMarkdown(text);
    if (blocks.isEmpty) {
      return Center(
        child: Text('还没有内容', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        for (final b in blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: noteRoot.renderBlock(context, b),
          ),
      ],
    );
  }
}
