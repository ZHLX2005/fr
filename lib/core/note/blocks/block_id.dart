/// 块 ID 生成器
///
/// 使用 UUID v4 保证全局唯一，避免多人协作冲突
class BlockId {
  static final _uuid = _Uuid();

  static String generate() => _uuid.v4();
}

/// 最小化 UUID v4 实现，无外部依赖
class _Uuid {
  String v4() {
    final bytes = List<int>.generate(16, (_) => _randomByte());
    // UUID v4: version 4 的标记位
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return _format(bytes);
  }

  int _randomByte() => DateTime.now().microsecondsSinceEpoch % 256 ^ _next();

  int _counter = 0;
  int _next() => ++_counter & 0xff;

  String _format(List<int> bytes) {
    final parts = [
      _hex(bytes, 0, 4),
      _hex(bytes, 4, 2),
      _hex(bytes, 6, 2),
      _hex(bytes, 8, 2),
      _hex(bytes, 10, 6),
    ];
    return parts.join('-');
  }

  String _hex(List<int> bytes, int start, int len) {
    final buf = StringBuffer();
    for (int i = start; i < start + len; i++) {
      buf.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }
}

/// 树路径寻址，用于 UI 导航和 Context Builder
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
