import 'dart:async';
import 'block.dart';
import 'block_type.dart';
import 'rich_text.dart';

/// 块树的变更描述（用于增量更新 UI）
sealed class TreeChange {
  final String parentId;
  final String blockId;

  const TreeChange(this.parentId, this.blockId);
}

class InsertedChange extends TreeChange {
  const InsertedChange(super.parentId, super.blockId);
}

class RemovedChange extends TreeChange {
  const RemovedChange(super.parentId, super.blockId);
}

class UpdatedChange extends TreeChange {
  final Map<String, dynamic>? oldValues;
  const UpdatedChange(super.parentId, super.blockId, [this.oldValues]);
}

class MovedChange extends TreeChange {
  final String oldParentId;
  const MovedChange(super.parentId, super.blockId, this.oldParentId);
}

/// 块树 —— 基于双索引（id→Block + id→parentId）的树结构
class BlockTree {
  /// 隐藏根节点
  static const rootId = '__root__';

  /// id → Block
  final Map<String, Block> _blocks = {};

  /// id → parentId
  final Map<String, String> _parents = {};

  /// parentId → [childId, ...]
  final Map<String, List<String>> _childrenOf = {};

  /// 变更流（用于 UI 增量更新）
  final StreamController<List<TreeChange>> _changeController =
      StreamController<List<TreeChange>>.broadcast(sync: true);
  Stream<List<TreeChange>> get changes => _changeController.stream;

  /// 构造：初始化根节点
  BlockTree() {
    _initRoot();
  }

  void _initRoot() {
    final root = Block(
      id: rootId,
      type: BlockType.page,
      content: RichText.text('Root'),
    );
    _blocks[rootId] = root;
    _parents[rootId] = rootId;
    _childrenOf[rootId] = [];
  }

  // ──────────── 查询 ────────────

  Block? get(String id) => _blocks[id];
  Block? parentOf(String id) => _parents[id] != null ? _blocks[_parents[id]!] : null;
  String? parentIdOf(String id) => _parents[id];
  List<String> childIdsOf(String id) => List.unmodifiable(_childrenOf[id] ?? []);
  List<Block> childrenOf(String id) => (_childrenOf[id] ?? [])
      .map((cid) => _blocks[cid]!)
      .toList();
  bool exists(String id) => _blocks.containsKey(id);
  bool isRoot(String id) => id == rootId;
  int get size => _blocks.length;

  /// 获取 block 的深度（根为 0）
  int depthOf(String id) {
    int depth = 0;
    var current = id;
    while (current != rootId) {
      current = _parents[current] ?? rootId;
      depth++;
    }
    return depth;
  }

  /// 从 id 到根的路径
  List<String> pathToRoot(String id) {
    final path = <String>[];
    var current = id;
    while (current != rootId) {
      path.add(current);
      current = _parents[current] ?? rootId;
    }
    return path.reversed.toList();
  }

  /// 扁平展开以 id 为中心的子树（用于 AI Context Builder）
  List<FlatBlock> flattenSince(String id, {int windowSize = 30}) {
    final all = <FlatBlock>[];
    _flattenRecursive(rootId, all, 0);

    final idx = all.indexWhere((f) => f.block.id == id);
    if (idx < 0) return all;

    final start = (idx - windowSize ~/ 2).clamp(0, all.length);
    final end = (idx + windowSize ~/ 2).clamp(0, all.length);
    return all.sublist(start, end);
  }

  void _flattenRecursive(String id, List<FlatBlock> result, int depth) {
    final block = _blocks[id];
    if (block == null) return;
    if (id != rootId) {
      result.add(FlatBlock(block, depth, _parents[id]!));
    }
    for (final childId in _childrenOf[id] ?? []) {
      _flattenRecursive(childId, result, depth + 1);
    }
  }

  // ──────────── 修改 ────────────

  /// 插入块
  void insert(Block block, {required String parentId, String? afterId}) {
    assert(block.id != rootId, '不能插入根节点');
    assert(!_blocks.containsKey(block.id), '块 ${block.id} 已存在');
    assert(_blocks.containsKey(parentId), '父块 $parentId 不存在');
    assert(afterId == null || _blocks.containsKey(afterId), 'after 块 $afterId 不存在');
    if (afterId != null) {
      assert(
        _parents[afterId] == parentId,
        'afterId $afterId 不在父块 $parentId 下',
      );
    }

    _blocks[block.id] = block;
    _parents[block.id] = parentId;

    final siblings = _childrenOf[parentId]!;
    if (afterId == null) {
      siblings.add(block.id);
    } else {
      final idx = siblings.indexOf(afterId);
      siblings.insert(idx + 1, block.id);
    }

    // 容器类块需要初始化 childrenOf
    _childrenOf.putIfAbsent(block.id, () => []);

    _emit([InsertedChange(parentId, block.id)]);
  }

  /// 更新块（部分更新）
  void update(String id, {RichText? content, BlockType? type, BlockData? data, Map<String, dynamic>? properties}) {
    final block = _blocks[id];
    if (block == null) return;

    final oldValues = <String, dynamic>{};
    if (content != null) oldValues['content'] = block.content;
    if (type != null) oldValues['type'] = block.type;
    if (data != null) oldValues['data'] = block.data;
    if (properties != null) oldValues['properties'] = block.properties;

    _blocks[id] = block.copyWith(
      content: content,
      type: type,
      data: data,
      properties: properties,
      updatedAt: DateTime.now(),
    );

    final parentId = _parents[id]!;
    _emit([UpdatedChange(parentId, id, oldValues)]);
  }

  /// 删除块及其子树
  Block? remove(String id) {
    if (id == rootId) return null;
    final block = _blocks[id];
    if (block == null) return null;

    // 先递归删除所有子块
    final childrenCopy = List<String>.from(_childrenOf[id] ?? []);
    for (final childId in childrenCopy) {
      remove(childId);
    }

    final parentId = _parents[id]!;
    _childrenOf[parentId]?.remove(id);
    _blocks.remove(id);
    _parents.remove(id);
    _childrenOf.remove(id);

    _emit([RemovedChange(parentId, id)]);
    return block;
  }

  /// 移动块
  void move(String id, {required String newParentId, String? afterId}) {
    assert(_blocks.containsKey(id), '块 $id 不存在');
    assert(_blocks.containsKey(newParentId), '目标父块 $newParentId 不存在');
    assert(!_wouldCreateCycle(id, newParentId), '移动会产生循环');

    final oldParentId = _parents[id]!;
    _childrenOf[oldParentId]?.remove(id);
    _parents[id] = newParentId;
    final siblings = _childrenOf.putIfAbsent(newParentId, () => []);
    if (afterId == null) {
      siblings.insert(0, id);
    } else {
      final idx = siblings.indexOf(afterId);
      siblings.insert(idx + 1, id);
    }

    _emit([MovedChange(newParentId, id, oldParentId)]);
  }

  /// 检测循环
  bool _wouldCreateCycle(String id, String newParentId) {
    var current = newParentId;
    while (current != rootId) {
      if (current == id) return true;
      current = _parents[current] ?? rootId;
    }
    return false;
  }

  /// 清空（保留根节点）
  void clear() {
    final root = _blocks[rootId]!;
    _blocks.clear();
    _childrenOf.clear();
    _parents.clear();
    _initRoot();
    _blocks[rootId] = root.copyWith(children: []);
    _emit([RemovedChange(rootId, rootId)]);
  }

  /// 从 JSON 重建树
  factory BlockTree.fromJson(List<Map<String, dynamic>> jsonBlocks) {
    final tree = BlockTree._bare();
    tree._rebuild(jsonBlocks);
    return tree;
  }

  BlockTree._bare();

  void _rebuild(List<Map<String, dynamic>> jsonBlocks) {
    _initRoot();
    // 递归注册块及其子块到 _blocks / _parents / _childrenOf
    void processBlock(Block block, String parentId) {
      _blocks[block.id] = block;
      _parents[block.id] = parentId;
      _childrenOf.putIfAbsent(parentId, () => []).add(block.id);
      _childrenOf.putIfAbsent(block.id, () => []);
      for (final child in block.children) {
        processBlock(child, block.id);
      }
    }

    for (final json in jsonBlocks) {
      final block = Block.fromJson(json);
      if (block.id == rootId) continue;
      processBlock(block, rootId);
    }
  }

  void _emit(List<TreeChange> changes) {
    if (!_changeController.isClosed) {
      _changeController.add(changes);
    }
  }

  void dispose() {
    _changeController.close();
  }
}

/// 扁平块（用于 AI Context Builder 的展开表示）
class FlatBlock {
  final Block block;
  final int depth;
  final String parentId;

  const FlatBlock(this.block, this.depth, this.parentId);
}
