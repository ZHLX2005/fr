import 'package:flutter/foundation.dart';
import '../../../core/note/core/block.dart';
import '../../../core/note/core/block_id.dart';
import '../../../core/note/core/block_type.dart';
import '../../../core/note/core/rich_text.dart';

/// Phase 1 简化的编辑器状态管理。
/// 后续接入完整 BlockTree + BlockOp + OperationHistory 后替换。
class EditorState extends ChangeNotifier {
  final List<Block> _blocks = [];
  String? _selectedId;

  List<Block> get blocks => List.unmodifiable(_blocks);
  String? get selectedId => _selectedId;
  Block? get selectedBlock =>
      _selectedId != null ? _blocks.where((b) => b.id == _selectedId).firstOrNull : null;

  void load(List<Block> blocks) {
    _blocks.addAll(blocks);
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
  }

  void deleteBlock() {
    final idx = _blocks.indexWhere((b) => b.id == _selectedId);
    if (idx < 0) return;
    _blocks.removeAt(idx);
    _selectedId = _blocks.isNotEmpty
        ? _blocks[idx.clamp(0, _blocks.length - 1)].id
        : null;
    notifyListeners();
  }

  void addBlock() {
    final block = Block(
      id: BlockId.generate(),
      type: BlockType.paragraph,
      content: RichText.text('新段落'),
    );
    _blocks.add(block);
    _selectedId = block.id;
    notifyListeners();
  }

  void updateContent(String id, String newText) {
    final idx = _blocks.indexWhere((b) => b.id == id);
    if (idx < 0) return;
    _blocks[idx] = _blocks[idx].copyWith(content: RichText.text(newText));
    notifyListeners();
  }

  void moveBlock(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    if (newIndex > oldIndex) newIndex--;
    final block = _blocks.removeAt(oldIndex);
    _blocks.insert(newIndex, block);
    notifyListeners();
  }
}
