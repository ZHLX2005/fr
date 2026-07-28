import 'package:hive_flutter/hive_flutter.dart';

/// 单个 Hive Box 的自描述结构
///
/// 每个 feature 只需在自己的 hive init 里 `StorageRegistry.register(...)`，
/// StorageManager 就能自动接管：显示卡片、格式化、删除、清空。
class BoxDescriptor<T> {
  /// Hive box 真实名称
  final String name;

  /// 面板显示的中文名（"日历事件"）
  final String displayName;

  /// typed box 的 typeId；null 表示是非 typed（普通 dynamic box）
  final int? typeId;

  /// typed box 打开器；非 typed 时用 [openUntyped]
  final Future<Box<T>> Function()? openTyped;

  /// 非 typed 打开器；typed 时用 [openTyped]
  final Future<Box> Function()? openUntyped;

  /// 值格式化器（面板"展开后每条 key 的显示"）；null 走默认 toString
  final String Function(dynamic value)? formatValue;

  /// 值大小估算器（面板显示 size）；null 走默认 toString().length
  final int Function(dynamic value)? estimateSize;

  const BoxDescriptor({
    required this.name,
    required this.displayName,
    this.typeId,
    this.openTyped,
    this.openUntyped,
    this.formatValue,
    this.estimateSize,
  });

  bool get isTyped => typeId != null;

  /// 打开 Box（如果未打开）
  Future<void> ensureOpen() async {
    if (Hive.isBoxOpen(name)) return;
    if (openTyped != null) {
      await openTyped!();
    } else if (openUntyped != null) {
      await openUntyped!();
    } else {
      await Hive.openBox(name);
    }
  }

  /// 获取已打开的 Box（用于遍历 keys）
  BoxBase getBox() {
    if (isTyped) {
      return Hive.box<T>(name);
    }
    return Hive.box(name);
  }

  /// 遍历所有 key（自动泛型/非泛型）
  Iterable<dynamic> get keys => getBox().keys;

  /// 按 key 取值
  dynamic get(dynamic key) {
    if (isTyped) {
      return Hive.box<T>(name).get(key);
    }
    return Hive.box(name).get(key);
  }

  /// box 的当前 length
  int get length => getBox().length;

  /// 删除单条
  Future<void> delete(dynamic key) => getBox().delete(key);

  /// 清空整个 box
  Future<void> clear() => getBox().clear();
}