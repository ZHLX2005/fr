import 'box_descriptor.dart';

/// 全局 Box 注册表
///
/// 每个 feature 的 hive init 处调用 `StorageRegistry.register(...)`，
/// StorageManager 通过 [all] 遍历所有注册项，完成"面板展示 / 格式化 / 删除 / 清空"，
/// 不再需要在 StorageManager 里加 if-else 分支。
///
/// 使用：
/// ```dart
/// StorageRegistry.register(BoxDescriptor<Event>(
///   name: 'calendarEvents',
///   displayName: '日历事件',
///   typeId: 90,
///   openTyped: () => Hive.openBox<Event>('calendarEvents'),
///   formatValue: (v) { final e = v as Event; return '标题: ${e.title}\n...'; },
/// ));
/// ```
class StorageRegistry {
  StorageRegistry._();

  static final Map<String, BoxDescriptor> _boxes = {};

  /// 注册一个 box；重复 name 会覆盖（幂等）
  static void register<T>(BoxDescriptor<T> d) {
    _boxes[d.name] = d;
  }

  /// 所有已注册的 box
  static Iterable<BoxDescriptor> get all => _boxes.values;

  /// 按 name 查找
  static BoxDescriptor? get(String name) => _boxes[name];

  /// 是否已注册
  static bool has(String name) => _boxes.containsKey(name);

  /// 清空所有注册（测试用）
  static void clear() => _boxes.clear();
}