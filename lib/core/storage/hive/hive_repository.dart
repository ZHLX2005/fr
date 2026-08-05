/// 持久化仓库标记接口。
///
/// 类似 Dart 社区惯用的「abstract class as tag」模式（参考 ChangeNotifier、
/// Listenable）。无方法体，纯声明。
///
/// 通过 `implements HiveRepository` 标识一个类是「按 boxName 可寻的
/// 持久化仓库」。未来想统一遍历/注册时用得到。
abstract class HiveRepository {
  /// box 名称（用于元数据查找 / 反射注册）。
  String get boxName;
}
