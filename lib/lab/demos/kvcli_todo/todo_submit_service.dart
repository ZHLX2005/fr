// KV 清单 —— 提交（读-改-写）的共享实现。
//
// 为什么必须只有一份：KV 后端没有"单条更新"API（见 kv_endpoint.dart 头注释），
// 所有写 = 读整把 key → 改数组 → 整把覆盖。如果 lab 页面和全局圆环各写一份
// _add()，下面三条契约迟早漂移：
//   1. id 分配必须扫 待办+冻结 —— 冻结任务保留原 id，只扫待办会在清空待办后
//      与冻结任务撞车，解冻时无法按 id 定位到正确任务。
//   2. topic 不在快捷列表时，要连 todo:topics 一起写。
//   3. 两把 key 一起写，失败整单放弃（不能写半截）。
//
// 竞态：写前重读，接受毫秒级竞态放弃（与页面 _refreshLatest 同策略）。
// KV 无单条更新 API，不重读会直接覆盖掉并发写（例如本机 kvcli CLI 同时写入）。

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/goframe/kv/kv_endpoint.dart';
import '../../../api/providers/api_providers.dart';
import 'const_kvcli_todo.dart';
import 'kvcli_todo_models.dart';

/// 提交计划 —— [TodoSubmitService.plan] 的纯计算结果，即两把 key 的目标值。
class TodoSubmitPlan {
  const TodoSubmitPlan({
    required this.tasks,
    required this.topics,
    required this.topicChanged,
  });

  /// `todo:open` 的目标值（已含新任务）。
  final List<KvTask> tasks;

  /// `todo:topics` 的目标值。
  final List<String> topics;

  /// false → topic 已在快捷列表里，不需要写 `todo:topics`。
  final bool topicChanged;
}

/// 提交服务。用法分两档：
///   - 页面已有内存快照 → [plan] 算出目标值，自己 setState + [apply]
///     （页面刚 _refreshLatest 过，不必让服务再读一遍）
///   - 无快照（全局圆环）→ [submitQuick] 自读自写
class TodoSubmitService {
  TodoSubmitService(this._kv);

  final KvEndpoint _kv;

  /// 激活组注入 KV 的三元值：0 → null（后端回落默认组），>0 → 原值。
  /// 页面与全局圆环共用，避免这个映射散落多处。
  static int? toGroupId(int activeGroup) => activeGroup == 0 ? null : activeGroup;

  /// 下一个可用任务 id：扫 待办+冻结 取最大 +1（原因见文件头注释第 1 条）。
  /// `_add` / `_cloneTask` / 解冻换 id 三处共用同一条规则。
  static int nextTaskId(List<KvTask> open, List<KvTask> freeze) {
    var maxId = 0;
    for (final t in [...open, ...freeze]) {
      if (t.id > maxId) maxId = t.id;
    }
    return maxId + 1;
  }

  /// 纯函数：本地快照 + 新任务 → 提交计划。不碰网络。
  static TodoSubmitPlan plan({
    required List<KvTask> open,
    required List<KvTask> freeze,
    required List<String> topics,
    required String topic,
    required String text,
    DateTime? now,
  }) {
    final task = KvTask(
      id: nextTaskId(open, freeze),
      topic: topic,
      text: text,
      createdAt: (now ?? DateTime.now()).toIso8601String(),
    );
    final topicChanged = !topics.contains(topic);

    return TodoSubmitPlan(
      tasks: [...open, task],
      topics: topicChanged ? [...topics, topic] : topics,
      topicChanged: topicChanged,
    );
  }

  /// 落盘：先 `todo:open` 后 `todo:topics`。任一步失败抛异常，调用方负责提示。
  Future<void> apply(TodoSubmitPlan plan, {int? groupId}) async {
    await _writeKey(
      KvCliTodoConst.keyOpen,
      jsonEncode(plan.tasks.map((t) => t.toJson()).toList()),
      groupId,
    );
    if (plan.topicChanged) {
      await _writeKey(KvCliTodoConst.keyTopics, jsonEncode(plan.topics), groupId);
    }
  }

  /// 读快捷 topic 列表。给提交面板做候选 chip 用（读失败返回空列表，不挡提交）。
  Future<List<String>> loadTopics({int? groupId}) => _readTopics(groupId);

  /// 全局圆环用：没有内存快照，自读 → plan → 落盘。
  /// 读的是 open/freeze/topics 三把 key（done 不参与 id 分配，不读）。
  Future<void> submitQuick({
    required String topic,
    required String text,
    int? groupId,
  }) async {
    final open = await _readTasks(KvCliTodoConst.keyOpen, groupId);
    final freeze = await _readTasks(KvCliTodoConst.keyFreeze, groupId);
    final topics = await _readTopics(groupId);
    await apply(
      plan(open: open, freeze: freeze, topics: topics, topic: topic, text: text),
      groupId: groupId,
    );
  }

  Future<List<KvTask>> _readTasks(String key, int? groupId) async {
    final res = await _kv.get(key, groupId: groupId);
    // key 不存在 / 后端返回失败：当作空数组
    if (!res.isSuccess || res.data == null) return const <KvTask>[];
    return KvTask.parseList(res.data!.value);
  }

  Future<List<String>> _readTopics(int? groupId) async {
    final res = await _kv.get(KvCliTodoConst.keyTopics, groupId: groupId);
    if (!res.isSuccess || res.data == null) return const <String>[];
    final raw = res.data!.value.trim();
    if (raw.isEmpty) return const <String>[];
    try {
      return (jsonDecode(raw) as List)
          .cast<String>()
          .where((s) => s.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _writeKey(String key, String value, int? groupId) async {
    final res = await _kv.set(key: key, value: value, ttl: 0, groupId: groupId);
    if (!res.isSuccess) {
      throw Exception('写 $key 失败: code=${res.code} ${res.message}');
    }
  }
}

/// 全局提交服务（全局圆环注入用）。
final todoSubmitServiceProvider = Provider<TodoSubmitService>(
  (ref) => TodoSubmitService(ref.watch(kvEndpointProvider)),
);
