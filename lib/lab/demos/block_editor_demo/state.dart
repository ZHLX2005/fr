import 'package:flutter/foundation.dart';
import '../../../core/note/core/core.dart';
import '../../../core/note/factory.dart';

/// 编辑器状态管理，支持持久化。
class EditorState extends ChangeNotifier {
  final List<Block> _blocks = [];
  String? _selectedId;
  String? _noteId;
  final NoteFactory _noteFactory;

  EditorState({required NoteFactory noteFactory})
    : _noteFactory = noteFactory;

  List<Block> get blocks => List.unmodifiable(_blocks);
  String? get selectedId => _selectedId;
  String? get noteId => _noteId;
  Block? get selectedBlock =>
      _selectedId != null ? _blocks.where((b) => b.id == _selectedId).firstOrNull : null;

  /// 从磁盘加载最近一篇笔记，无笔记则新建空状态。
  Future<void> init() async {
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
    _blocks.add(Block(
      id: _noteFactory.generateId(),
      type: const ParagraphType(),
      content: RichText.text(''),
    ));
    _selectedId = _blocks.first.id;
    await _save();
    notifyListeners();
  }

  void select(String id) {
    _selectedId = id;
    notifyListeners();
  }

  void clearSelection() {
    _selectedId = null;
    notifyListeners();
  }

  void toggleType(BlockType newType) {
    final idx = _blocks.indexWhere((b) => b.id == _selectedId);
    if (idx < 0) return;
    _blocks[idx] = _blocks[idx].copyWith(type: newType);
    notifyListeners();
    _save();
  }

  void deleteBlock() {
    final idx = _blocks.indexWhere((b) => b.id == _selectedId);
    if (idx < 0) return;
    _blocks.removeAt(idx);
    _selectedId = _blocks.isNotEmpty
        ? _blocks[idx.clamp(0, _blocks.length - 1)].id
        : null;
    notifyListeners();
    _save();
  }

  void addBlock() {
    final block = Block(
      id: _noteFactory.generateId(),
      type: const ParagraphType(),
      content: RichText.text(''),
    );
    _blocks.add(block);
    _selectedId = block.id;
    notifyListeners();
    _save();
  }

  void updateContent(String id, String newText) {
    final idx = _blocks.indexWhere((b) => b.id == id);
    if (idx < 0) return;
    _blocks[idx] = _blocks[idx].copyWith(content: RichText.text(newText));
    notifyListeners();
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

  void addBlockWithType(BlockType type) {
    final block = Block(
      id: _noteFactory.generateId(),
      type: type,
      content: type.containerOnly ? RichText.empty() : RichText.text(''),
    );
    if (_selectedId != null) {
      final idx = _blocks.indexWhere((b) => b.id == _selectedId);
      if (idx >= 0) {
        _blocks.insert(idx + 1, block);
        _selectedId = block.id;
        notifyListeners();
        _save();
        return;
      }
    }
    _blocks.add(block);
    _selectedId = block.id;
    notifyListeners();
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

  /// 导入 markdown 内容，替换当前笔记的所有块。
  void importMd(String source) {
    final blocks = _noteFactory.parseMarkdown(source);
    if (blocks.isEmpty) return;
    _blocks
      ..clear()
      ..addAll(blocks);
    _selectedId = _blocks.first.id;
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    if (_noteId == null) return;
    final root = Block(
      id: _noteId!,
      type: const PageType(),
      content: RichText.text(_extractTitle()),
      children: List.of(_blocks),
    );
    await _noteFactory.saveNote(root);
  }

  /// 删除指定笔记。若是当前笔记，自动切换到下一笔记或新建。
  Future<void> deleteNote(String id) async {
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
