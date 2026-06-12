import 'package:flutter/foundation.dart';
import '../../../core/note/note_root_scope.dart';
import 'mode/toolbar_factory.dart';
import 'ai/ai_models.dart';

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

  // === AI 对话状态 ===

  /// blockId → BlockAIConversation
  final Map<String, BlockAIConversation> _aiConversations = {};

  /// 当前正在展示 AI Bar 的 block id
  String? _activeAiBarBlockId;

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

  /// 发送 AI 请求
  Future<void> sendAiPrompt(String blockId, String prompt) async {
    if (prompt.isEmpty) return;

    // 关闭 AI Bar
    _activeAiBarBlockId = null;

    // 获取或创建对话
    final conv = _aiConversations.putIfAbsent(
      blockId,
      () => BlockAIConversation(blockId: blockId),
    );

    // 添加用户消息
    conv.addMessage(AIChatMessage.user(prompt));

    // 添加 loading
    conv.addMessage(AIChatMessage.loading());

    notifyListeners();

    // mock AI 回复
    await Future.delayed(const Duration(seconds: 1));

    conv.removeLoading();
    conv.addMessage(AIChatMessage.ai('已完成请求："$prompt"'));
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
