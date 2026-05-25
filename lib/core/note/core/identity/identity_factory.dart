import 'block_id.dart';
import 'block_path.dart';

/// Identity 统一工厂。
///
/// 所有 ID 生成和路径构造都通过此工厂收敛，
/// 底层实现可随时替换（如从纯 Dart UUID 切换到平台 UUID）。
class BlockIdentityFactory {
  const BlockIdentityFactory._();

  /// 生成全局唯一块 ID。
  static String generateId() => BlockId.generate();

  /// 构造树路径。
  static BlockPath path(List<String> ids) => BlockPath(ids);

  /// 从路径字符串反构造。
  static BlockPath pathFromString(String path) => BlockPath.fromString(path);
}
