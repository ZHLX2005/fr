import 'dart:typed_data';

import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart' show TextInputFormatter, TextEditingValue;

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
/// ## 第 9 轮（反馈：「全面优化 md 编辑器，支持上传图片」）
///
/// 调研过开源方案（AppFlowy Editor / flutter_quill / fleather / markdown_widget /
/// super_editor），**不引入编辑器依赖**：这页的约束是「预览与块编辑器同一套渲染」
/// （`NoteFactory.renderBlock`），换一套编辑内核等于把这条约束拆了，而那几个包
/// 要么是另一套 Delta 范式、要么依赖重/发版停滞。采纳的是它们的**实践**：
///
///   · **贴图走附件仓**（面板同款 `POST /api/file`）：选图 → base64 上传 → 把
///     服务端生成的 `![名](fileId)` 片段插进光标处。任务入库时服务端自动登记
///     附件关系，端侧不用再调 attach；预览与任务正文都能把 fileId 画成图
///     （经 [MdImageResolver] 桥取字节）。
///   · **回车自动续列表**：`- ` / `1. ` / `- [ ] ` / `> ` 在敲回车时自动延续，
///     空列表项上再敲一次回车退出（TextInputFormatter 实现，程序化插入不走它）。
///   · **字数统计**贴在提交条上（开源编辑器的标配，写反馈时知道写了多少）。
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

/// 贴图入口：选图 + 上传，返回**服务端生成的嵌入片段**（`![名](fileId)`）。
///
/// 编辑器不关心图从哪来（相册/相机）、传到哪去 —— 那是装配方的活；
/// 它只负责「拿到片段插进正文 + 上传期间把按钮转起来」。抛错由编辑器接住弹提示。
typedef MdImagePicker = Future<String> Function();

/// 预览里 fileId 图片的取字节回调（经桥）。null = 预览不画 fileId 图，
/// 显示占位（不是报错 —— 没接桥的装配方不该因此坏掉）。
typedef MdImageResolver = Future<Uint8List?> Function(String fileId);

/// 打开 md 编辑器（整页，返回 null = 取消）。
Future<String?> openMdComposer(
  BuildContext context, {
  required String title,
  String hint = '支持 Markdown：# 标题、- 列表、> 引用、```代码',
  String initialText = '',
  /// 初始光标位置（null = 编辑器自己的默认：文末）。模板正文很长时要把光标
  /// 放到该改的那一处（新建任务是标题行），否则一进来就停在文末。
  int? initialCaret,
  String submitLabel = '提交',
  String? quote,
  bool showPreview = true,
  bool showInsertBlock = true,
  List<String> templates = const [],
  MdImagePicker? pickImage,
  MdImageResolver? imageResolver,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => MdComposerPage(
        title: title,
        hint: hint,
        initialText: initialText,
        initialCaret: initialCaret,
        submitLabel: submitLabel,
        quote: quote,
        showPreview: showPreview,
        showInsertBlock: showInsertBlock,
        templates: templates,
        pickImage: pickImage,
        imageResolver: imageResolver,
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
    this.initialCaret,
    this.quote,
    this.showPreview = true,
    this.showInsertBlock = true,
    this.templates = const [],
    this.pickImage,
    this.imageResolver,
  });

  final String title;
  final String hint;
  final String initialText;

  /// 打开时的光标位置（null = 默认文末）；越界一律忽略，不抛。
  final int? initialCaret;

  final String submitLabel;

  /// 锚定原文（划线评价时给）：只读展示，提交时由调用方带进 `--quote`。
  final String? quote;

  final bool showPreview;
  final bool showInsertBlock;

  /// 模板片段（点一下插到末尾）：如「完成总结」的四段式。
  final List<String> templates;

  /// 贴图入口；null = 不显示图片按钮（见 [MdImagePicker]）。
  final MdImagePicker? pickImage;

  /// 预览取 fileId 图片字节；null = 预览不画 fileId 图（见 [MdImageResolver]）。
  final MdImageResolver? imageResolver;

  @override
  State<MdComposerPage> createState() => _MdComposerPageState();
}

class _MdComposerPageState extends State<MdComposerPage> {
  late final TextEditingController _controller = _initialController();

  /// 初始文本 + 初始光标。光标越界/没给 → 交给编辑器默认（文末），不报错：
  /// 调用方算错一个下标不该让人打不开编辑器。
  TextEditingController _initialController() {
    final c = TextEditingController(text: widget.initialText);
    final at = widget.initialCaret;
    if (at != null && at >= 0 && at <= widget.initialText.length) {
      c.selection = TextSelection.collapsed(offset: at);
    }
    return c;
  }
  final _focus = FocusNode();
  bool _preview = false;

  /// 贴图上传中：图片按钮变成小转圈，提交条禁用（一次只传一张，别把正文插乱）
  bool _uploading = false;

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

  /// 在**光标处**插入（贴图用）：图片落在人正看着的地方，不挪到文末。
  /// 前后各补空行，保证嵌入独立成段（md 的图片语法必须独占一行才渲染）。
  void _insertAtCaret(String snippet) {
    final value = _controller.value;
    final text = value.text;
    final caret = value.selection.isValid ? value.selection.end : text.length;
    final before = text.substring(0, caret);
    final after = text.substring(caret);
    final lead = before.isEmpty || before.endsWith('\n\n') ? '' : (before.endsWith('\n') ? '\n' : '\n\n');
    final tail = after.isEmpty || after.startsWith('\n\n') ? '' : (after.startsWith('\n') ? '\n' : '\n\n');
    final next = '$before$lead$snippet$tail$after';
    final at = before.length + lead.length + snippet.length;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at),
    );
    _focus.requestFocus();
  }

  /// 贴图：装配方的 [MdImagePicker] 负责选图与上传，这里只管插与提示。
  /// 返回空串 = 用户取消（没选图），什么都不做。
  Future<void> _pickAndInsertImage() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final snippet = await widget.pickImage!();
      if (!mounted || snippet.isEmpty) return;
      _insertAtCaret(snippet);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('图片传不上去：$e', style: const TextStyle(fontSize: 12))),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
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
        child: Column(
          children: [
            _topBar(cs),
            if (widget.quote != null && widget.quote!.trim().isNotEmpty) _QuoteAnchor(text: widget.quote!),
            Expanded(
              child: _preview
                  ? _Preview(text: _controller.text, imageResolver: widget.imageResolver)
                  : _editor(cs),
            ),
            _toolbar(cs),
            // 提交条放在 body 里，**不做 bottomNavigationBar**。
            // Scaffold 只把 body 让给键盘：底栏永远是「屏幕底 − 自身高度」
            // （SDK `scaffold.dart` 的 `bottomNavigationBarTop = bottom - height`），
            // 键盘一弹，整颗「派发任务」就落在键盘背面 —— 手指点不到，看着像按钮没了。
            // 放进 Column 尾巴上，它天然被 body 的收缩顶到键盘上沿。
            _submitBar(cs, canSave),
          ],
        ),
      ),
    );
  }

  /// 48dp 提交条：字数 + 整行按钮。
  Widget _submitBar(ColorScheme cs, bool canSave) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, AppSpacing.md, AppSpacing.sm),
      child: Row(
        children: [
          // 字数（不含空白）：开源编辑器的标配 —— 写反馈时知道写了多少
          Text(
            '${_controller.text.replaceAll(RegExp(r'\s'), '').length} 字',
            style: TextStyle(fontSize: 10, color: cs.outline),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: SizedBox(
              height: 40,
              child: FilledButton(
                // 主题给 FilledButton 配了 vertical: 14 的内边距；在 40dp 高的
                // 提交条里会把单行中文挤到只剩 12dp，底部笔画被裁掉。
                // 这里覆盖成零纵向内边距，让按钮自己把文字垂直居中。
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size.fromHeight(40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: canSave && !_uploading
                    ? () => Navigator.of(context).pop(_controller.text.trim())
                    : null,
                child: Text(widget.submitLabel),
              ),
            ),
          ),
        ],
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
        // 回车自动续列表：键盘敲进去的换行在这里拦（程序化插入不经过 formatter，
        // 所以模板/贴图的插入不会被误加前缀）
        inputFormatters: const [MdListContinuation()],
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
          // 贴图：面板同款链路（选图 → 附件仓 → 嵌入片段插光标处）。
          // 上传中转圈并禁点 —— 一次一张，插乱正文比慢更伤。
          if (widget.pickImage != null)
            _uploading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 11),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : btn(Icons.image_outlined, '插入图片（经 PC 附件仓）', _pickAndInsertImage),
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
  const _Preview({required this.text, this.imageResolver});

  final String text;

  /// 预览取 fileId 图片字节；null = 显示占位（见 [MdImageResolver]）。
  final MdImageResolver? imageResolver;

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
            child: _blockOrAttachment(context, noteRoot, b),
          ),
      ],
    );
  }

  /// fileId 图片经 [MdImageResolver] 取字节画（通用渲染器只认 http/本地文件）；
  /// 其余块照旧走 NoteFactory —— 预览与块编辑器同一套渲染的约束不破。
  Widget _blockOrAttachment(BuildContext context, NoteFactory noteRoot, Block b) {
    final resolver = imageResolver;
    if (resolver != null && b.type is ImageType) {
      final t = b.type as ImageType;
      final src = t.src.trim();
      if (looksLikeAttachmentFileId(src)) {
        return MdRemoteImage(resolver: resolver, fileId: src, alt: t.caption ?? '');
      }
    }
    return noteRoot.renderBlock(context, b);
  }
}

/// 这段图片 `src` 是不是附件仓的不透明 id（要经桥取字节的那种）。
///
/// 口径与 nx-kv 面板 `shared/attach.ts` 的 FILE_ID_RE 一致：≥16 位 hex、可带
/// 一个短扩展名。URL（含 `://`）与路径都不匹配 —— 判定窄是刻意的，正文里一条
/// 普通图片链接不会被误认成附件。放编辑器这边而不是 api 层：预览是通用渲染，
/// 不该为这个判定反向依赖 nxkv。
final RegExp _attachmentFileIdRe = RegExp(r'^[0-9a-fA-F]{16,}(\.[A-Za-z0-9]{1,8})?$');

bool looksLikeAttachmentFileId(String src) => _attachmentFileIdRe.hasMatch(src.trim());

/// 回车自动续列表：上一行是 `- ` / `1. ` / `- [ ] ` / `> ` 开头时，
/// 新行自动带上同样的前缀；空列表项上再敲回车 = 退出列表（把空项删掉）。
///
/// 用 [TextInputFormatter] 而不是 `onChanged` 比对：formatter 拿到的是**这次编辑**
/// 的精确 delta，不会在快速连打时误判；且只拦「插入了一个 \n」这一种编辑。
class MdListContinuation extends TextInputFormatter {
  const MdListContinuation();

  static final _prefix = RegExp(r'^(\s*)(?:(- \[[ x]\] |[-*] |\d+\. |> )(.*))$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final oldText = oldValue.text;
    final newText = newValue.text;
    // 只处理「光标处插了一个换行」这一种编辑
    if (newText.length != oldText.length + 1) return newValue;
    final sel = newValue.selection;
    if (!sel.isValid || sel.baseOffset != sel.extentOffset) return newValue;
    final caret = sel.baseOffset;
    if (caret == 0 || newText.substring(0, caret) != '${oldText.substring(0, caret - 1)}\n') {
      return newValue;
    }

    // 找换行所在的那一行（新行的上一行）
    final lineStart = oldText.lastIndexOf('\n', caret - 2) + 1;
    final line = oldText.substring(lineStart, caret - 1);
    final m = _prefix.firstMatch(line);
    if (m == null) return newValue;

    final indent = m.group(1)!;
    final prefix = m.group(2)!;
    final content = m.group(3)!.trim();
    // 空列表项上再敲回车 = 退出列表：把空项连同它**前面的换行**一起删掉
    //（上一行的终止符），光标落回上一行末尾 —— 这是所有 md 编辑器的合并语义。
    // 空项就是第一行时没有前换行，从行首删起。
    if (content.isEmpty) {
      final lineStart0 = lineStart;
      final start = lineStart0 > 0 ? lineStart0 - 1 : lineStart0;
      final next = newText.replaceRange(start, caret, '');
      return TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: start),
      );
    }
    // 序号列表续号：`3. ` 的下一行是 `4. `
    final numbered = RegExp(r'^(\d+)\. $').firstMatch(prefix);
    final continued = numbered != null ? '${int.parse(numbered.group(1)!) + 1}. ' : prefix;
    // 换行本身已经在这次编辑里了，这里只补前缀（多补一个 \n 会空一行）
    final insertion = '$indent$continued';
    final next = newText.replaceRange(caret, caret, insertion);
    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret + insertion.length),
    );
  }
}

/// 预览里的 fileId 图片：字节经桥取回（[MdImageResolver]），画不好就给占位，
/// **不连累整页预览** —— 一张传不回的图不该让其它段落也看不见。
class MdRemoteImage extends StatefulWidget {
  const MdRemoteImage({
    super.key,
    required this.resolver,
    required this.fileId,
    required this.alt,
  });

  final MdImageResolver resolver;
  final String fileId;
  final String alt;

  @override
  State<MdRemoteImage> createState() => _MdRemoteImageState();
}

class _MdRemoteImageState extends State<MdRemoteImage> {
  late Future<Uint8List?> _future = _load();

  /// resolver 同步抛错（比如 fileId 校验不过）也要收成**失败的 Future**，
  /// 否则异常会冲出 build —— 一张图把整页预览干成红屏，违背本组件的存在理由。
  ///
  /// 而且错误必须在**源头**就吃掉：重试时这个 Future 生成在 setState 里、
  /// 直到下一帧 FutureBuilder 才订阅，中间那一拍没人监听，Dart 会按
  /// 「未处理异常」上报 —— 线上就是一段红字。兜底值 null 走占位分支。
  Future<Uint8List?> _load() async {
    try {
      return await widget.resolver(widget.fileId);
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text('正从 PC 传过来…', style: TextStyle(fontSize: 10, color: cs.outline)),
              ],
            ),
          );
        }
        final bytes = snap.data;
        if (snap.hasError || bytes == null || bytes.isEmpty) {
          return GestureDetector(
            // 块体不能是箭头函数：赋值表达式的值是 Future，setState 会把
            // 「回调返回了 Future」当错误抛 —— 这是块体语句才有的坑
            onTap: () {
              setState(() {
                _future = _load();
              });
            },
            child: Row(
              children: [
                Icon(Icons.broken_image_outlined, size: 14, color: cs.error),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.alt.isEmpty ? '这张图画不出来（点按重试）' : '${widget.alt}（画不出来，点按重试）',
                    style: TextStyle(fontSize: 10, color: cs.error),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(
            bytes,
            width: double.infinity,
            fit: BoxFit.contain,
            alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) => Text('这张图画不出来（格式不支持）', style: TextStyle(fontSize: 10, color: cs.outline)),
          ),
        );
      },
    );
  }
}
