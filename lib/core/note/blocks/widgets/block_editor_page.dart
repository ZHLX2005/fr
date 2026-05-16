import 'dart:convert';
import 'package:flutter/material.dart' hide RichText;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../workspace/workspace_provider.dart';
import '../../../../models/ai_chat_message.dart' show AISettings;
import '../ai/ai_tools.dart';
import '../ai/note_ai_service.dart';
import '../ai/prompts/prompts.dart';
import '../block.dart';
import '../block_id.dart';
import '../block_editor_controller.dart';
import '../block_tree.dart';
import '../block_type.dart';
import '../rich_text.dart';
import 'ai_conversation_bar.dart';
import 'block_widget.dart';
import 'sidebar.dart';

/// 块编辑器主页面
class BlockEditorPage extends StatefulWidget {
  final BlockEditorController? controller;
  final String? title;

  const BlockEditorPage({
    super.key,
    this.controller,
    this.title,
  });

  @override
  State<BlockEditorPage> createState() => _BlockEditorPageState();
}

class _BlockEditorPageState extends State<BlockEditorPage> {
  late BlockEditorController _controller;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  final Map<String, FocusNode> _focusNodes = {};

  // AI 对话状态
  final List<ConversationMessage> _conversationMessages = [];
  bool _aiLoading = false;
  String _aiStatusText = '正在思考…';
  final NoteAiService _aiService = NoteAiService();

  @override
  void dispose() {
    _scrollController.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _focusNodeFor(String blockId) {
    return _focusNodes.putIfAbsent(blockId, () => FocusNode());
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceProvider>();

    // 从工作区获取当前页面的控制器
    if (ws.initialized && ws.activePage != null) {
      _controller = ws.activePage!.controller;
    } else {
      // 等待工作区初始化
      return Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Text(widget.title ?? '笔记编辑器',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
          ws.activePage?.title ?? widget.title ?? '笔记编辑器',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF242424) : const Color(0xFFFAFAFA),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '展开侧边栏',
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        ],
      ),
      drawer: const Sidebar(),
      body: Container(
        color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF),
        child: Column(
          children: [
            Expanded(child: _buildBlockList(isDark)),
            if (_controller.aiBarVisible) _buildAIConversationPanel(isDark),
            if (_controller.morePanelVisible) _buildMorePanel(isDark),
            _buildBottomBar(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockList(bool isDark) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final blocks = _getFlatBlocks();
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: blocks.length,
          itemBuilder: (context, index) {
            final entry = blocks[index];
            final isSelected = entry.block.id == _controller.selectedBlockId;

            return Padding(
              padding: EdgeInsets.only(left: entry.depth * 20.0),
              child: BlockWidget(
                key: ValueKey(entry.block.id),
                block: entry.block,
                isSelected: isSelected,
                focusNode: _focusNodeFor(entry.block.id),
                onTap: (id) => _onSelectBlock(id),
                onChanged: (text) => _onBlockChanged(entry.block.id, text),
                onSubmitted: (_) => _onBlockSubmit(entry.block.id, index),
                onDeleteEmpty: () => _onDeleteBlock(entry.block.id, index),
              ),
            );
          },
        );
      },
    );
  }

  void _onSelectBlock(String id) {
    _controller.selectBlock(id);
    // 延迟确保 focus 请求生效
    Future.microtask(() {
      _focusNodeFor(id).requestFocus();
    });
  }

  void _onBlockChanged(String blockId, String text) {
    // Markdown 快捷输入检测（仅对段落生效）
    final shortcut = _matchMdShortcut(blockId, text);
    if (shortcut != null) {
      _controller.tree.update(blockId,
        type: shortcut.type,
        content: RichText.text(shortcut.content),
        data: shortcut.data,
      );
      return;
    }
    _controller.tree.update(blockId, content: RichText.text(text));
  }

  void _onBlockSubmit(String blockId, int index) {
    final block = _controller.tree.get(blockId);
    // 分隔线：--- 回车
    if (block != null && block.type == BlockType.paragraph && block.content.toPlainText().trimLeft() == '---') {
      _controller.tree.update(blockId, type: BlockType.divider, content: RichText.empty());
      final parentId = _controller.tree.parentIdOf(blockId) ?? BlockTree.rootId;
      final newBlock = Block(id: BlockId.generate(), type: BlockType.paragraph);
      _controller.tree.insert(newBlock, parentId: parentId, afterId: blockId);
      _controller.selectBlock(newBlock.id);
      Future.microtask(() => _focusNodeFor(newBlock.id).requestFocus());
      return;
    }
    // 默认：新建段落
    final parentId = _controller.tree.parentIdOf(blockId) ?? BlockTree.rootId;
    final newBlock = Block(
      id: BlockId.generate(),
      type: BlockType.paragraph,
    );
    _controller.tree.insert(newBlock, parentId: parentId, afterId: blockId);
    _controller.selectBlock(newBlock.id);
    Future.microtask(() {
      _focusNodeFor(newBlock.id).requestFocus();
    });
  }

  /// Markdown 快捷输入匹配
  _MdShortcut? _matchMdShortcut(String blockId, String text) {
    final block = _controller.tree.get(blockId);
    if (block == null || block.type != BlockType.paragraph) return null;
    // 仅对单行文本生效（有换行说明已输入多行，不再转换）
    if (text.contains('\n')) return null;

    // 代码块 ``` 或 `````
    if (text.startsWith('```')) {
      final lang = text.substring(3).trim();
      return _MdShortcut(BlockType.code, '', BlockData.fromMap({'language': lang}));
    }

    // 标题 # ~ ######
    final headingMatch = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(text);
    if (headingMatch != null) {
      final level = headingMatch.group(1)!.length;
      return _MdShortcut(BlockType.heading, headingMatch.group(2) ?? '',
          BlockData.fromMap({'level': level}));
    }

    // 引用 >
    final quoteMatch = RegExp(r'^>\s+(.*)$').firstMatch(text);
    if (quoteMatch != null) {
      return _MdShortcut(BlockType.quote, quoteMatch.group(1) ?? '', BlockData.empty());
    }

    // 待办 [ ] / [x]
    final todoMatch = RegExp(r'^\[([ xX])\]\s+(.*)$').firstMatch(text);
    if (todoMatch != null) {
      final checked = todoMatch.group(1)!.toLowerCase() == 'x';
      return _MdShortcut(BlockType.todo, todoMatch.group(2) ?? '',
          BlockData.fromMap({'checked': checked}));
    }

    // 无序列表 -
    final ulMatch = RegExp(r'^-\s+(.*)$').firstMatch(text);
    if (ulMatch != null) {
      return _MdShortcut(BlockType.bulletListItem, ulMatch.group(1) ?? '', BlockData.empty());
    }

    // 有序列表 1.
    final olMatch = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(text);
    if (olMatch != null) {
      final number = int.tryParse(olMatch.group(1) ?? '') ?? 1;
      return _MdShortcut(BlockType.orderedListItem, olMatch.group(2) ?? '',
          BlockData.fromMap({'number': number}));
    }

    return null;
  }

  void _onDeleteBlock(String blockId, int index) {
    if (blockId == BlockTree.rootId) return;
    // 找上一个同级块或父块
    final parentId = _controller.tree.parentIdOf(blockId);
    if (parentId == null) return;

    final siblings = _controller.tree.childIdsOf(parentId);
    final idx = siblings.indexOf(blockId);
    final prevId = idx > 0 ? siblings[idx - 1] : parentId;

    _controller.tree.remove(blockId);
    _focusNodes.remove(blockId);

    _controller.selectBlock(prevId);
    Future.microtask(() {
      _focusNodeFor(prevId).requestFocus();
    });
  }

  /// 在选中块的末尾插入行内 Markdown 语法
  void _applyMd(String prefix, String suffix, String placeholder) {
    final id = _controller.selectedBlockId;
    if (id == null) return;
    final block = _controller.tree.get(id);
    if (block == null) return;
    // 跳过不可编辑的类型
    if (block.type == BlockType.page || block.type == BlockType.divider ||
        block.type == BlockType.image || block.type == BlockType.embedCard ||
        block.type == BlockType.database || block.type == BlockType.bookmark ||
        block.type == BlockType.equation || block.type == BlockType.syncedBlock) {
      return;
    }
    final text = block.content.toPlainText();
    _controller.tree.update(id, content: RichText.text('$text$prefix$placeholder$suffix'));
  }

  List<_FlatEntry> _getFlatBlocks() {
    final result = <_FlatEntry>[];
    _flatten(BlockTree.rootId, 0, result);
    return result;
  }

  void _flatten(String parentId, int depth, List<_FlatEntry> result) {
    for (final childId in _controller.tree.childIdsOf(parentId)) {
      final block = _controller.tree.get(childId);
      if (block == null) continue;
      result.add(_FlatEntry(block, depth));
      if (block.canHaveChildren) {
        _flatten(childId, depth + 1, result);
      }
    }
  }

  // ──────────── AI 对话面板 ────────────

  Widget _buildAIConversationPanel(bool isDark) {
    return AIConversationBar(
      messages: _conversationMessages,
      isLoading: _aiLoading,
      loadingStatus: _aiStatusText,
      onSend: _sendAIMessage,
      onClose: () => setState(() => _controller.aiBarVisible = false),
      onClear: () => setState(_conversationMessages.clear),
    );
  }

  /// 发送消息给 AI 并处理 agent 循环
  Future<void> _sendAIMessage(String text) async {
    setState(() {
      _conversationMessages.add(ConversationMessage.user(text));
      _aiLoading = true;
      _aiStatusText = '正在思考…';
    });

    final ws = context.read<WorkspaceProvider>();

    // 确保 AI 服务已配置
    await _ensureAiConfigured();
    if (!_aiService.isConfigured) {
      setState(() {
        _conversationMessages.add(
          ConversationMessage.assistant('请先在侧边栏 → AI 设置中配置 API Key'),
        );
        _aiLoading = false;
      });
      return;
    }

    final systemPrompt = buildSystemPrompt(ws, _controller);
    final apiMessages = _buildApiMessages();
    final allToolCalls = <ToolCallInfo>[];
    String? finalReply;
    String? finalError;
    bool wroteContent = false;
    int turn;

    // Agent 循环：最大 5 轮防止无限循环
    for (turn = 0; turn < 5; turn++) {
      setState(() => _aiStatusText = turn == 0 ? '正在思考…' : '继续处理…');

      // 最后一轮使用最强力的提示
      if (turn == 4 && !wroteContent && isActionRequest(text)) {
        apiMessages.add({
          'role': 'user',
          'content': '这是最后一次机会，必须立即直接调用 write_content 工具将内容写入当前页面。不要读取、不要回复文字、不要犹豫，直接写入。',
        });
      }

      final result = await _aiService.chat(
        messages: apiMessages,
        systemPrompt: systemPrompt,
        tools: AiToolbox.toJsonList(),
      );

      if (result.isError) {
        finalError = result.error;
        break;
      }

      if (!result.hasToolCalls) {
        if (turn > 0 && isActionRequest(text) && onlyReadTools(allToolCalls)) {
          setState(() => _aiStatusText = '强制写入…');
          apiMessages.add({
            'role': 'user',
            'content':
                '你刚刚只是读取了内容，没有实际写入。请使用 write_content 向当前页面写入 Markdown 内容，或使用 ai_create_page 创建新页面。不要只回复文字。',
          });
          continue;
        }
        if (turn == 0 && isActionRequest(text) && allToolCalls.isEmpty) {
          setState(() => _aiStatusText = '强制使用工具…');
          apiMessages.add({
            'role': 'user',
            'content':
                '请使用可用的工具来实际执行操作。只回复文字不算真正执行——必须调用工具才能完成。不要回复"Why are you sending this again"类疑问——直接执行你被要求执行的操作。',
          });
          continue;
        }
        // 无更多工具调用 —— 本轮回复为最终消息
        finalReply = result.reply;
        break;
      }

      allToolCalls.addAll(result.toolCalls);

      apiMessages.add({
        'role': 'assistant',
        'content': result.reply,
        'tool_calls':
            result.toolCalls.map((tc) => tc.toAssistantMessageMap()).toList(),
      });

      for (final tc in result.toolCalls) {
        setState(() => _aiStatusText = '执行: ${tc.name}…');
        final toolResult = await _executeToolCall(tc, ws);
        if (_isWriteTool(tc.name) &&
            !toolResult.startsWith('操作失败') &&
            !toolResult.startsWith('工具') &&
            !toolResult.startsWith('未知工具')) {
          wroteContent = true;
        }
        apiMessages.add({
          'role': 'tool',
          'tool_call_id': tc.id,
          'content': toolResult,
        });
      }
    }

    // turn >= 5 表示循环耗尽（未 break）
    final bool loopExhausted = turn >= 5;

    if (mounted) {
      setState(() {
        if (finalError != null) {
          _conversationMessages.add(
            ConversationMessage.assistant('出错了: $finalError'),
          );
        } else if (loopExhausted && !wroteContent && isActionRequest(text)) {
          _conversationMessages.add(
            ConversationMessage.assistant('AI 未能完成操作，请重试或检查 AI 设置是否正常。'),
          );
        } else {
          _conversationMessages.add(
            ConversationMessage.assistant(
              finalReply ?? (wroteContent ? '已完成' : '未能完成操作'),
              toolCalls: allToolCalls.isNotEmpty ? allToolCalls : null,
            ),
          );
        }
        _aiLoading = false;
      });
    }
  }

  /// 判断工具名称是否为写入型工具
  bool _isWriteTool(String name) {
    const writeTools = {
      'write_content', 'insert_block', 'update_block',
      'ai_create_page', 'merge_blocks', 'split_block',
      'move_block', 'delete_block',
    };
    return writeTools.contains(name);
  }

  /// 执行单个工具调用
  Future<String> _executeToolCall(ToolCallInfo tc, WorkspaceProvider ws) async {
    final name = tc.name;
    Map<String, dynamic> args;
    try {
      args = jsonDecode(tc.arguments) as Map<String, dynamic>;
    } catch (_) {
      args = {};
    }

    try {
      switch (name) {
        // ── 只读工具 ──
        case 'read_block':
          return _readBlock(args);
        case 'read_subtree':
          return _readSubtree(args);
        case 'search_blocks':
          return _searchBlocks(args);

        // ── 写入工具（委托 AiAgent）──
        case 'insert_block':
        case 'update_block':
        case 'delete_block':
        case 'move_block':
        case 'merge_blocks':
        case 'split_block': {
          final call = <String, dynamic>{'name': name, 'arguments': args};
          final result = _controller.aiAgent.processToolCalls(
            [call],
            selectedId: _controller.selectedBlockId,
          );
          return result.success
              ? (result.summary.isNotEmpty ? result.summary : '操作成功')
              : '操作失败: ${result.errors.map((e) => e.toString()).join("; ")}';
        }

        // ── 工作区级工具 ──
        case 'ai_create_page': {
          final title = args['title'] as String? ?? '未命名笔记';
          final content = args['content'] as String? ?? '';
          ws.createPage(title: title);
          if (content.isNotEmpty) {
            // 切换到新页面后，用新页面的控制器插入块
            final newCtrl = ws.activePage!.controller;
            final lines = content.split('\n');
            String? prevId;
            for (final line in lines) {
              if (line.trim().isEmpty) continue;
              final block = parseMdLine(line);
              newCtrl.tree.insert(block, parentId: BlockTree.rootId, afterId: prevId);
              prevId = block.id;
            }
          }
          return '已创建页面「$title」${content.isNotEmpty ? '，已填入内容' : ''}，已自动切换。';
        }

        // ── 高层次的 Markdown 写入工具 ──
        case 'write_content': {
          final content = args['content'] as String? ?? '';
          final replace = args['replace'] as bool? ?? false;
          if (content.isEmpty) return '内容为空';
          if (replace) {
            for (final childId
                in _controller.tree.childIdsOf(BlockTree.rootId).toList()) {
              _controller.tree.remove(childId);
            }
          }
          final lines = content.split('\n');
          String? prevId;
          int count = 0;
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            final block = parseMdLine(line);
            _controller.tree.insert(
                block, parentId: BlockTree.rootId, afterId: prevId);
            prevId = block.id;
            count++;
          }
          return '已写入 $count 个块';
        }

        // ── 占位工具 ──
        case 'format_text':
          return 'format_text 暂未实现';

        default:
          return '未知工具: $name';
      }
    } catch (e) {
      return '工具 $name 执行异常: $e';
    }
  }

  // ── 只读工具实现 ──

  String _readBlock(Map<String, dynamic> args) {
    final id = args['id'] as String? ?? '';
    final block = _controller.tree.get(id);
    if (block == null) return '块不存在: $id';
    return 'ID: ${block.id}\n类型: ${block.type.tag}\n内容: ${block.content.toPlainText()}';
  }

  String _readSubtree(Map<String, dynamic> args) {
    final id = args['id'] as String? ?? '';
    final depth = args['depth'] as int? ?? 3;
    final buf = StringBuffer();
    _buildSubtreeText(id, 0, depth.clamp(1, 5), buf);
    return buf.toString();
  }

  void _buildSubtreeText(String blockId, int currentDepth, int maxDepth, StringBuffer buf) {
    final block = _controller.tree.get(blockId);
    if (block == null) return;
    final indent = '  ' * currentDepth;
    buf.writeln('$indent- [${block.type.tag}] ${block.content.toPlainText()}');
    if (currentDepth < maxDepth && block.canHaveChildren) {
      for (final childId in _controller.tree.childIdsOf(blockId)) {
        _buildSubtreeText(childId, currentDepth + 1, maxDepth, buf);
      }
    }
  }

  String _searchBlocks(Map<String, dynamic> args) {
    final query = (args['query'] as String? ?? '').toLowerCase();
    final limit = args['limit'] as int? ?? 10;
    if (query.isEmpty) return '查询条件为空';

    final results = <String>[];
    _searchRecursive(BlockTree.rootId, query, results);
    if (results.isEmpty) return '未找到匹配的内容';
    return results.take(limit.clamp(1, 50)).join('\n');
  }

  void _searchRecursive(String parentId, String query, List<String> results) {
    for (final childId in _controller.tree.childIdsOf(parentId)) {
      final block = _controller.tree.get(childId);
      if (block == null) continue;
      final text = block.content.toPlainText();
      if (text.toLowerCase().contains(query)) {
        results.add('- [${block.type.tag}] $text (id: ${block.id})');
      }
      if (block.canHaveChildren) {
        _searchRecursive(childId, query, results);
      }
    }
  }

  // ── 工具方法 ──

  /// 从对话历史构建 API 消息列表（不含 system 消息）
  List<Map<String, dynamic>> _buildApiMessages() {
    final msgs = <Map<String, dynamic>>[];
    for (final m in _conversationMessages) {
      switch (m.role) {
        case 'user':
          msgs.add({'role': 'user', 'content': m.content});
          break;
        case 'assistant':
          // 只传文字内容，不传历史 tool_calls（旧 tool_calls 对应的 tool result
          // 未持久化到 _conversationMessages，传出去会导致 API 格式错误）
          msgs.add({'role': 'assistant', 'content': m.content});
          break;
        case 'tool':
          msgs.add({
            'role': 'tool',
            'tool_call_id': m.toolCallId ?? '',
            'content': m.content,
          });
          break;
      }
    }
    return msgs;
  }

  /// 从 SharedPreferences 加载 AI 配置
  Future<void> _ensureAiConfigured() async {
    if (_aiService.isConfigured) return;
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('ai_chat_settings');
    if (json != null && json.isNotEmpty) {
      _aiService.updateFromSettings(AISettings.decode(json));
    }
  }

  // ──────────── 更多面板 ────────────

  Widget _buildMorePanel(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFFAFAFA),
        border: Border(
            top: BorderSide(
                color: isDark ? const Color(0xFF3D3D3D) : const Color(0xFFE0E0E0))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('标题级别',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF9E9E9E) : const Color(0xFF757575))),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(6, (i) {
                  final level = i + 1;
                  return _panelButton('H$level', () => _controller.setHeader(level), isDark);
                }),
              ),
              const SizedBox(height: 16),
              Text('段落',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF9E9E9E) : const Color(0xFF757575))),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  _panelButton('正文', () => _controller.toggleType(BlockType.paragraph), isDark),
                  _panelButton('引用', () => _controller.toggleType(BlockType.quote), isDark),
                  _panelButton('分割线', () {
                    _insertDivider();
                    setState(() => _controller.morePanelVisible = false);
                  }, isDark),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelButton(String label, VoidCallback onTap, bool isDark) {
    return Material(
      color: isDark ? const Color(0xFF3D3D3D) : const Color(0xFFE0E0E0),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFFE0E0E0) : const Color(0xFF2D2D2D))),
        ),
      ),
    );
  }

  void _insertDivider() {
    if (_controller.selectedBlockId == null) return;
    final afterId = _controller.selectedBlockId!;
    final parentId = _controller.tree.parentIdOf(afterId) ?? BlockTree.rootId;
    final divider = Block(id: BlockId.generate(), type: BlockType.divider);
    _controller.tree.insert(divider, parentId: parentId, afterId: afterId);
    _controller.selectBlock(divider.id);
  }

  // ──────────── 底部工具栏 ────────────

  Widget _buildBottomBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFFAFAFA),
        border: Border(
            top: BorderSide(
                color: isDark ? const Color(0xFF3D3D3D) : const Color(0xFFE0E0E0))),
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              _toolbarButton(
                icon: Icons.auto_awesome,
                tooltip: 'AI 助手',
                onPressed: () => setState(() {
                  _controller.aiBarVisible = true;
                  _controller.morePanelVisible = false;
                }),
                isHighlight: true,
                highlightColor: isDark ? const Color(0xFFFFCA28) : const Color(0xFFFFD54F),
              ),
              const SizedBox(width: 8),
              _divider(isDark),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _iconBtn(Icons.format_bold, '粗体', () => _applyMd('**', '**', '粗体'), false, isDark),
                      _iconBtn(Icons.format_italic, '斜体', () => _applyMd('*', '*', '斜体'), false, isDark),
                      _iconBtn(Icons.code, '行内代码', () => _applyMd('`', '`', '代码'), false, isDark),
                      const SizedBox(width: 4),
                      _iconBtn(Icons.format_quote, '引用',
                          () => _controller.toggleType(BlockType.quote), false, isDark),
                      _iconBtn(Icons.format_list_bulleted, '无序列表',
                          () => _controller.toggleType(BlockType.bulletListItem), false, isDark),
                      _iconBtn(Icons.format_list_numbered, '有序列表',
                          () => _controller.toggleType(BlockType.orderedListItem), false, isDark),
                      const SizedBox(width: 8),
                      _divider(isDark),
                      const SizedBox(width: 8),
                      _iconBtn(Icons.add_box_outlined, '嵌入卡片', () {}, false, isDark),
                      const SizedBox(width: 8),
                      _divider(isDark),
                      const SizedBox(width: 8),
                      _iconBtn(Icons.add, '更多格式', () {
                        setState(() {
                          _controller.morePanelVisible = !_controller.morePanelVisible;
                          _controller.aiBarVisible = false;
                        });
                      }, isDark, true, isDark),
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

  Widget _toolbarButton({
    IconData? icon,
    String? label,
    required String tooltip,
    required VoidCallback? onPressed,
    bool isHighlight = false,
    Color? highlightColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultColor = isDark ? const Color(0xFF9E9E9E) : const Color(0xFF757575);
    final activeColor = isHighlight
        ? (highlightColor ?? defaultColor)
        : (isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2));

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.all(8),
            child: icon != null
                ? Icon(icon, size: 22, color: onPressed == null ? defaultColor.withValues(alpha: 0.4) : activeColor)
                : Text(label ?? '',
                    style: TextStyle(fontSize: 13, color: activeColor)),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap, bool isActive, bool isDark, [bool invert = false]) {
    final activeColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, size: 22, color: isActive ? activeColor : (isDark ? const Color(0xFF9E9E9E) : const Color(0xFF757575))),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider(bool isDark) {
    return Container(width: 1, height: 24, color: isDark ? const Color(0xFF3D3D3D) : const Color(0xFFE0E0E0));
  }
}

/// Markdown 快捷输入匹配结果
class _MdShortcut {
  final BlockType type;
  final String content;
  final BlockData data;
  const _MdShortcut(this.type, this.content, this.data);
}

/// 扁平块条目（块 + 缩进深度）
class _FlatEntry {
  final Block block;
  final int depth;
  const _FlatEntry(this.block, this.depth);
}
