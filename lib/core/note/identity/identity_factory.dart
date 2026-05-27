/// Identity 统一工厂。
///
/// 所有 ID 生成都通过此工厂收敛，
/// 底层实现可随时替换（如从纯 Dart UUID 切换到平台 UUID）。
class BlockIdentityFactory {
  final _IdGenerator _idGenerator;

  BlockIdentityFactory() : _idGenerator = _IdGenerator();

  /// 生成全局唯一块 ID。
  String generateId() => _idGenerator.v4();
}

/// UUID v4 生成器。纯 Dart 实现，无外部依赖。
class _IdGenerator {
  _IdGenerator();

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
