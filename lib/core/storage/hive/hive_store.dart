import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 统一管理 Hive 初始化 + box 句柄缓存。
/// 所有 Repository 都通过它打开 box，避免重复 initFlutter / openBox。
class HiveStore {
  HiveStore._();
  static final HiveStore instance = HiveStore._();
  bool _initialized = false;
  final Map<String, Box<dynamic>> _boxes = {};

  /// 初始化 Hive（多次调用安全）。
  ///
  /// 测试开关：true 时 init() 不调 initFlutter（那需要 path_provider
  /// 平台通道，测试环境没有）。测试在 setUp 里先 `Hive.init(tempDir)`
  /// 再置此开关，生产代码不碰它。
  static bool skipFlutterInitForTest = false;

  Future<void> init() async {
    if (_initialized) return;
    if (skipFlutterInitForTest) {
      debugPrint('[HiveStore] skipFlutterInitForTest：跳过 initFlutter');
    } else {
      await Hive.initFlutter();
    }
    _initialized = true;
  }

  /// 打开 untyped box（Map 序列化场景）。
  /// 多次调用同一 box 返回缓存句柄。
  /// 首次打开用 Hive.openBox()，之后直接返回缓存（避免 `Hive.box()` 抛
  /// `Box not found` —— `Hive.box()` 不会自动打开未 open 的 box）。
  Future<Box<dynamic>> openUntyped(String name) async {
    await init();
    if (_boxes.containsKey(name)) return _boxes[name]!;
    final box = Hive.isBoxOpen(name)
        ? Hive.box<dynamic>(name)
        : await Hive.openBox<dynamic>(name);
    _boxes[name] = box;
    return box;
  }

  /// 给 typed box 用的便捷方法（registerAdapter + openBox 合并）。
  Future<Box<T>> openTyped<T>(
    String name, {
    required TypeAdapter<T> adapter,
    int? typeId,
  }) async {
    await init();
    final id = typeId ?? adapter.typeId;
    if (!Hive.isAdapterRegistered(id)) {
      Hive.registerAdapter(adapter);
    }
    if (Hive.isBoxOpen(name)) return Hive.box<T>(name);
    final box = await Hive.openBox<T>(name);
    _boxes[name] = box;
    return box;
  }
}
