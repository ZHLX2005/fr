/// 全局唯一块 ID。生成 UUID v4，无外部依赖。
///
/// ID 是 Block 的身份标识，决定了 [Block.==] 和 [Block.hashCode]。
/// 多人协作场景下保证 ID 不冲突。
class BlockId {
  static final _uuid = _Uuid();
  static String generate() => _uuid.v4();
}

class _Uuid {
  String v4() {
    final bytes = List<int>.generate(16, (_) => _randomByte());
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return _format(bytes);
  }

  int _randomByte() =>
      DateTime.now().microsecondsSinceEpoch % 256 ^ _next();

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
