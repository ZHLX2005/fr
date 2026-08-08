import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'const_kvcli_todo.dart';

/// 激活工作空间（groupId）。0 = 服务端默认组。
/// 独立 ref 存储：页面 watch 取当前值、notifier 负责载入/持久化。
final activeGroupProvider =
    StateNotifierProvider<ActiveGroupNotifier, int>((ref) => ActiveGroupNotifier());

class ActiveGroupNotifier extends StateNotifier<int> {
  ActiveGroupNotifier() : super(0);

  /// 从 SharedPreferences 载入激活组（key kvtodo-default-group），失败回落 0。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getInt(KvCliTodoConst.prefActiveGroup) ?? 0;
      state = id < 0 ? 0 : id;
    } catch (_) {
      state = 0;
    }
  }

  /// 设置激活组并持久化；持久化失败不阻断本次切换。
  Future<void> set(int id) async {
    state = id < 0 ? 0 : id;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(KvCliTodoConst.prefActiveGroup, state);
    } catch (_) {}
  }
}
