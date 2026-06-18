import 'package:flutter/foundation.dart';
import '../../../core/note/note_root_scope.dart';
import 'mode/toolbar_factory.dart';
import 'ai/ai_models.dart';
import 'ai/ai_settings_store.dart';
import 'ai/article_edit_service.dart';
import 'ai/ai_chat_service.dart';

/// 编辑器状态管理，支持持久化。
class EditorState extends ChangeNotifier {
  final List<Block> _blocks = [];
  String? _selectedId;
  String? _noteId;

  /// 当前显示删除菜单的 block id（仅容器块有效）。
  /// 共享状态：任意位置点击都可关闭。
  String? _deleteMenuBlockId;

  final BottomToolbarFactory toolbarFactory;

  void switchToEdit() => toolbarFactory.switchTo('edit');

  final NoteFactory _noteFactory;

  /// 暴露 NoteFactory（供外部组装 ArticleEditService）。
  NoteFactory get noteFactorySafe => _noteFactory;

  // === AI 对话状态 ===

  /// blockId → BlockAIConversation
  final Map<String, BlockAIConversation> _aiConversations = {};

  /// 当前正在展示 AI Bar 的 block id
  String? _activeAiBarBlockId;

  /// 当前正在加载 AI 的 block id（用于显示 loading 状态）
  String? _aiLoadingBlockId;

  /// 当前 AI 请求是否已被用户取消 — 返回结果时若为 true 则丢弃。
  /// 注意：当前实现仅前端丢弃响应（不等结果），后端 agent 仍会跑完。
  /// 超时改 120s 后用户基本无需取消；保留 cancel 是兜底。
  bool _aiCanceled = false;

  /// AI 回复结果缓存：blockId → 解析后的 Block 列表
  final Map<String, List<Block>> _aiResults = {};

  /// AI 编辑的 diff 缓存：blockId → diff 文本（hasEdit=true 时有值）。
  final Map<String, String> _aiDiff = {};

  /// AI 错误信息（未配置/请求失败等）。
  String? _aiError;

  /// 注入的 article/edit 服务（null = 未接入后端）。
  ArticleEditService? _articleEditService;

  /// 注入的 ai/chat 服务（null = 未接入后端，对话小窗用）。
  AiChatService? _aiChatService;

  /// 当前 AI 配置。
  AiSettings _aiSettings = const AiSettings();

  /// Backspace 级联保护（放在 EditorState 中不随 widget 销毁）
  DateTime? _lastBackspaceDelete;
  static const _backspaceCooldown = Duration(milliseconds: 400);

  /// 检查是否处于 Backspace 冷却中，不在则记录时间并返回 false
  bool isBackspaceOnCooldown() {
    final now = DateTime.now();
    if (_lastBackspaceDelete != null &&
        now.difference(_lastBackspaceDelete!) < _backspaceCooldown) {
      return true;
    }
    _lastBackspaceDelete = now;
    return false;
  }

  EditorState({required NoteFactory noteFactory, BottomToolbarFactory? toolbarFactory})
    : _noteFactory = noteFactory,
      toolbarFactory = toolbarFactory ?? BottomToolbarFactory();

  List<Block> get blocks => List.unmodifiable(_blocks);
  String? get selectedId => _selectedId;
  String? get noteId => _noteId;
  Block? get selectedBlock =>
      _selectedId != null ? _blocks.where((b) => b.id == _selectedId).firstOrNull : null;

  /// 删除菜单当前所在 block id。
  String? get deleteMenuBlockId => _deleteMenuBlockId;
  bool isDeleteMenuShown(String blockId) => _deleteMenuBlockId == blockId;

  /// 当前 block 是否为 AI Bar 模式
  bool get isAiBarActive => _activeAiBarBlockId != null;
  String? get activeAiBarBlockId => _activeAiBarBlockId;
  bool isAiBarForBlock(String blockId) => _activeAiBarBlockId == blockId;

  /// 获取 block 的 AI 对话
  BlockAIConversation? getConversation(String blockId) => _aiConversations[blockId];

  /// 是否有 AI 气泡
  bool hasAiBubble(String blockId) =>
      _aiConversations[blockId]?.hasConversation ?? false;

  /// AI Bar 是否正在加载
  bool isAiLoading(String blockId) => _aiLoadingBlockId == blockId;

  /// 获取 AI 回复的 Block 列表
  List<Block>? getAiResult(String blockId) => _aiResults[blockId];

  /// block 是否正在显示 AI 回复 inline
  bool isAiShowingResult(String blockId) => _aiResults.containsKey(blockId);

  /// 某 block 的 AI diff（无则 null）。
  String? aiDiffFor(String blockId) => _aiDiff[blockId];

  /// 当前 AI 错误信息（UI 展示用）。
  String? get aiError => _aiError;

  /// 是否已配置 apiKey。
  bool get isAiConfigured => _aiSettings.isConfigured && _articleEditService != null;

  /// 对话小窗直接访问（不判空 — 调用方决定如何处理）。
  /// 暴露 chat service 是为了让 Overlay 注入的 widget 不必再走 riverpod。
  AiChatService? get aiChatServiceUnsafe => _aiChatService;
  AiSettings get aiSettingsUnsafe => _aiSettings;

  /// 注入 article/edit 服务。
  void setArticleEditService(ArticleEditService? service) {
    _articleEditService = service;
  }

  /// 注入 ai/chat 服务（对话小窗用）。
  void setAiChatService(AiChatService? service) {
    _aiChatService = service;
  }

  /// 更新 AI 配置（设置页保存后调用）。
  void updateAiSettings(AiSettings settings) {
    _aiSettings = settings;
    notifyListeners();
  }

  /// 激活 AI Bar（空格触发），同时选中该 block。
  void activateAiBar(String blockId) {
    _selectedId = blockId;
    _deleteMenuBlockId = null;
    _activeAiBarBlockId = blockId;
    notifyListeners();
  }

  /// 取消 AI Bar（Escape）
  void deactivateAiBar() {
    _activeAiBarBlockId = null;
    notifyListeners();
  }

  /// 发送 AI 请求 — 调用后端 article/edit 做全文编辑。
  Future<void> sendAiPrompt(String blockId, String prompt) async {
    if (prompt.isEmpty) return;

    // 未接入或未配置 → 提示
    if (_articleEditService == null || !_aiSettings.isConfigured) {
      _aiError = '请先在设置中配置 API Key';
      _activeAiBarBlockId = null;
      notifyListeners();
      return;
    }

    // 进入 loading
    _activeAiBarBlockId = null;
    _aiLoadingBlockId = blockId;
    _aiResults.remove(blockId);
    _aiDiff.remove(blockId);
    _aiError = null;
    _aiCanceled = false;
    notifyListeners();

    try {
      // 构造整篇笔记的 Block（PageType root + 当前所有 block 作 children）
      final root = _noteFactory.createBlock(
        const PageType(),
        id: _noteId ?? _noteFactory.generateId(),
        content: RichText.text(_extractTitle()),
        children: List<Block>.of(_blocks),
      );

      final result = await _articleEditService!.edit(
        rootNote: root,
        prompt: prompt,
        settings: _aiSettings,
      );

      if (_aiCanceled) return; // 用户已取消，丢弃响应

      if (result.hasEdit && result.modifiedBlock != null) {
        _aiDiff[blockId] = result.diff;
        _aiResults[blockId] = result.modifiedBlock!.children;
      } else {
        // 纯问答：conclusion 作为单个段落
        _aiResults[blockId] = [
          _noteFactory.createBlock(
            const ParagraphType(),
            content: RichText.text(result.conclusion),
          ),
        ];
      }
    } catch (e) {
      if (_aiCanceled) return;
      _aiError = 'AI 请求失败：$e';
    } finally {
      _aiLoadingBlockId = null;
      _aiCanceled = false;
      notifyListeners();
    }
  }

  /// 用户主动取消当前 AI 请求。
  /// 行为：丢弃响应、退出 loading、回到可编辑态（不显错误）。
  void cancelAiRequest() {
    if (_aiLoadingBlockId == null) return;
    _aiCanceled = true;
    _aiLoadingBlockId = null;
    _aiError = null;
    notifyListeners();
  }

  /// 确认 AI 回复：用结果替换整篇笔记（全文编辑语义）。
  /// 若无 diff（纯问答结果），退化为把单段结论追加到当前 block 之后。
  void confirmAiResult(String blockId) {
    final blocks = _aiResults.remove(blockId);
    final hasDiff = _aiDiff.remove(blockId) != null;
    if (blocks == null || blocks.isEmpty) return;

    if (hasDiff) {
      // 全文替换
      _blocks
        ..clear()
        ..addAll(blocks);
    } else {
      // 纯问答：插入到当前 block 之后
      final idx = _blocks.indexWhere((b) => b.id == blockId);
      if (idx >= 0) {
        _blocks.insertAll(idx + 1, blocks);
      } else {
        _blocks.addAll(blocks);
      }
    }

    _selectedId = blocks.isNotEmpty ? blocks.first.id : null;
    notifyListeners();
    _save();
  }

  /// 清除 AI 回复结果（及对应的 diff）。
  void clearAiResult(String blockId) {
    _aiResults.remove(blockId);
    _aiDiff.remove(blockId);
    _aiError = null;
    notifyListeners();
  }

  // === 删除菜单 ===

  /// 显示某 block 的删除菜单。已显示则忽略。
  void showDeleteMenu(String blockId) {
    if (_deleteMenuBlockId == blockId) return;
    _deleteMenuBlockId = blockId;
    notifyListeners();
  }

  /// 关闭删除菜单（任意点击其他区域调用）。
  void hideDeleteMenu() {
    if (_deleteMenuBlockId == null) return;
    _deleteMenuBlockId = null;
    notifyListeners();
  }

  /// 从磁盘加载最近一篇笔记，无笔记则新建空状态。
  Future<void> init() async {
    try {
      final notes = await _noteFactory.listNotes();
      if (notes.isNotEmpty) {
        final first = notes.first;
        _noteId = first.id;
        final root = await _noteFactory.loadNote(first.id);
        if (root != null) {
          _blocks.addAll(root.children);
        }
      }
      if (_blocks.isEmpty) {
        _noteId = _noteFactory.generateId();
      }
      if (_blocks.isNotEmpty) {
        _selectedId = _blocks.first.id;
      }
    } catch (e) {
      _noteId = _noteFactory.generateId();
    }
    notifyListeners();
  }

  /// 切换到指定笔记。
  Future<void> switchNote(String id) async {
    final root = await _noteFactory.loadNote(id);
    if (root == null) return;
    _noteId = id;
    _blocks.clear();
    _blocks.addAll(root.children);
    _selectedId = _blocks.isNotEmpty ? _blocks.first.id : null;
    notifyListeners();
  }

  /// 创建一篇空白新笔记（含一个空段落，立即保存到磁盘）。
  Future<void> createNewNote() async {
    _noteId = _noteFactory.generateId();
    _blocks.clear();
    _blocks.add(_noteFactory.createBlock(const ParagraphType()));
    _selectedId = _blocks.first.id;
    await _save();
    notifyListeners();
  }

  void select(String id) {
    _selectedId = id;
    // 选中其他 block 时，关闭删除菜单
    _deleteMenuBlockId = null;
    // 选中其他 block 时，关闭 AI Bar
    if (_activeAiBarBlockId != null && _activeAiBarBlockId != id) {
      _activeAiBarBlockId = null;
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedId = null;
    _deleteMenuBlockId = null;
    _activeAiBarBlockId = null;
    notifyListeners();
  }

  void toggleType(BlockType newType) {
    final idx = _blocks.indexWhere((b) => b.id == _selectedId);
    if (idx < 0) return;
    _blocks[idx] = _blocks[idx].copyWith(type: newType);
    notifyListeners();
    _save();
  }

  /// [silent] 为 true 时仅更新数据、保存，不触发 notifyListeners。
  /// 用于键盘输入回调中：先静默更新，再由调用方在 postFrameCallback 中
  /// 调用 [refresh] 延迟刷新 UI，避免打断 TextInputConnection。
  void deleteBlock({bool silent = false}) {
    final idx = _blocks.indexWhere((b) => b.id == _selectedId);
    if (idx < 0) return;
    _blocks.removeAt(idx);
    _selectedId = _blocks.isNotEmpty && idx > 0
        ? _blocks[(idx - 1).clamp(0, _blocks.length - 1)].id
        : null;
    _deleteMenuBlockId = null;
    _activeAiBarBlockId = null;
    if (!silent) notifyListeners();
    _save();
  }

  void addBlock({bool silent = false}) {
    final block = _noteFactory.createBlock(const ParagraphType());
    _blocks.add(block);
    _selectedId = block.id;
    if (!silent) notifyListeners();
    _save();
  }

  /// [silent] 见 [deleteBlock]。
  void updateContent(String id, String newText, {bool silent = false}) {
    final idx = _blocks.indexWhere((b) => b.id == id);
    if (idx < 0) return;

    // 仅 ParagraphType 检查类型转换
    if (_blocks[idx].type is ParagraphType) {
      final result = _noteFactory.tryConvert(newText);
      if (result != null) {
        final (type, rest) = result;
        _blocks[idx] = _blocks[idx].copyWith(
          type: type,
          content: RichText.text(rest),
        );
        if (!silent) notifyListeners();
        _save();
        return;
      }
    }

    _blocks[idx] = _blocks[idx].copyWith(content: RichText.text(newText));
    if (!silent) notifyListeners();
    _save();
  }

  void updateImageSrc(String id, String src) {
    final idx = _blocks.indexWhere((b) => b.id == id);
    if (idx < 0) return;
    final oldType = _blocks[idx].type as ImageType;
    _blocks[idx] = _blocks[idx].copyWith(type: oldType.copyWith(src: src));
    notifyListeners();
    _save();
  }

  /// [silent] 见 [deleteBlock]。
  void addBlockWithType(BlockType type, {bool silent = false}) {
    final block = _noteFactory.createBlock(type);
    if (_selectedId != null) {
      final idx = _blocks.indexWhere((b) => b.id == _selectedId);
      if (idx >= 0) {
        _blocks.insert(idx + 1, block);
        _selectedId = block.id;
        if (!silent) notifyListeners();
        _save();
        return;
      }
    }
    _blocks.add(block);
    _selectedId = block.id;
    if (!silent) notifyListeners();
    _save();
  }

  void toggleTodo(String id) {
    final idx = _blocks.indexWhere((b) => b.id == id);
    if (idx < 0) return;
    final block = _blocks[idx];
    final checked = (block.type as TodoType).checked;
    _blocks[idx] = block.copyWith(type: TodoType(checked: !checked));
    notifyListeners();
    _save();
  }

  void moveBlock(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    if (newIndex > oldIndex) newIndex--;
    final block = _blocks.removeAt(oldIndex);
    _blocks.insert(newIndex, block);
    notifyListeners();
    _save();
  }

  Future<void>? _pendingSave;

  /// 导入 markdown 内容，添加到当前光标位置之后。
  /// 无选中块则追加到文末。
  void importMd(String source) {
    final blocks = _noteFactory.parseMarkdown(source);
    if (blocks.isEmpty) return;

    if (_selectedId != null) {
      final idx = _blocks.indexWhere((b) => b.id == _selectedId);
      if (idx >= 0) {
        _blocks.insertAll(idx + 1, blocks);
        _selectedId = blocks.last.id;
        notifyListeners();
        _save();
        return;
      }
    }
    _blocks.addAll(blocks);
    _selectedId = blocks.last.id;
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    if (_noteId == null) return;
    final noteId = _noteId!;
    final blocks = List<Block>.of(_blocks);
    // 串联保存操作，防止并发写入竞争
    _pendingSave = (_pendingSave ?? Future.value()).then((_) =>
      _noteFactory.saveNote(
        _noteFactory.createBlock(
          const PageType(),
          id: noteId,
          content: RichText.text(_extractTitle()),
          children: blocks,
        ),
      ),
    );
  }

  /// 删除指定笔记。若是当前笔记，自动切换到下一笔记或新建。
  Future<void> deleteNote(String id) async {
    await _pendingSave;
    await _noteFactory.deleteNote(id);
    // 再次删除以捕获任何延迟写入
    await _noteFactory.deleteNote(id);
    if (id == _noteId) {
      final notes = await _noteFactory.listNotes();
      if (notes.isNotEmpty) {
        await switchNote(notes.first.id);
      } else {
        await createNewNote();
      }
    }
  }

  /// 延迟刷新：用于键盘输入回调中，在 postFrameCallback 里调用，
  /// 让 TextInputConnection 不被打断。
  void refresh() => notifyListeners();

  String _extractTitle() {
    for (final block in _blocks) {
      if (block.type is HeadingType) {
        final t = block.content.toPlainText().trim();
        if (t.isNotEmpty) return t;
      }
    }
    if (_blocks.isNotEmpty) {
      final t = _blocks.first.content.toPlainText().trim();
      if (t.isNotEmpty) {
        return t.length > 40 ? '${t.substring(0, 40)}…' : t;
      }
    }
    return '未命名笔记';
  }
}
