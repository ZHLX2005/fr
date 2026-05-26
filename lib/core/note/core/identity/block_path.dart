/// 树路径寻址。记录从根到目标块的 ID 序列。
///
/// 用于 UI 导航恢复和 AI Context Builder 的路径描述。
class BlockPath {
  final List<String> ids;

  const BlockPath(this.ids);

  String get last => ids.last;

  BlockPath append(String id) => BlockPath([...ids, id]);

  BlockPath removeLast() =>
      ids.length <= 1 ? this : BlockPath(ids.sublist(0, ids.length - 1));

  @override
  String toString() => ids.join('/');

  factory BlockPath.fromString(String path) => BlockPath(path.split('/'));

  static const root = BlockPath(['__root__']);
}

