# kv 清单工作空间（group）支持 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 kv 清单（`kvcli_todo_demo`）支持工作空间：查询我的工作空间、切换激活组（本地持久化 `kvtodo-default-group`）、所有 KV 操作带 groupId（三元：不为空才 set）。

**Architecture:** 新增 `GroupEndpoint`（查询 groups）+ `KvEndpoint` 4 方法加可选 `groupId` + 独立激活组 ref 存储（`ActiveGroupNotifier`，persist SharedPreferences）+ demo（`ConsumerStatefulWidget`）注入与 AppBar/bottom sheet UI。groupId 只有 kv 清单传；其他调用方（cloud_storage_sync 等）不传、走默认组。

**Tech Stack:** Flutter / flutter_riverpod ^2.6.1（StateNotifierProvider、ConsumerStatefulWidget）/ SharedPreferences / GoFrame KV 后端（47.110.80.47:8988）。

## Global Constraints

- **不运行 `flutter run`**。编译检查 = `flutter analyze <改动文件>`（必须无 error）。
- **每完成一个任务 = 一次 commit + 推送**（CI 构建 APK）。`git add` 只列本任务改动的文件，**禁止 `add .` / `commit .`**；提交前先 `git status`。
- commit message 沿用 `fix(scope):` / `feat(scope):` 风格。
- lab demo 辅助文件放已建好的 `lib/lab/demos/kvcli_todo/`；常量进 `const_kvcli_todo.dart`。
- `KvOps` 接口（cloud_storage_sync 依赖）**不改**；`groupId` 只加在具体类 `KvEndpoint` 上（Dart 允许 override 增补可选命名参数）。
- groupId 语义：`0` / `null` 不携带 → 后端回落服务端默认组（与 kvcli `GroupID > 0` 才注入一致）。

---

## Task 1: 基建 — GroupEndpoint + KvEndpoint groupId + 常量

**Files:**
- Create: `lib/api/goframe/group/group_endpoint.dart`
- Modify: `lib/api/goframe/kv/kv_endpoint.dart`（4 方法加 `int? groupId` + `_gidQuery` helper）
- Modify: `lib/api/providers/api_providers.dart`（import + `groupEndpointProvider`）
- Modify: `lib/lab/demos/kvcli_todo/const_kvcli_todo.dart`（`prefActiveGroup`）

**Interfaces:**
- Produces: `class GroupEndpoint`（`Future<ApiResponse<List<KvGroup>>> list()`）、`class KvGroup{int id; String name; String description; String myRole; int memberCount;}`；`KvEndpoint.get/set/delete/list` 各带可选 `int? groupId`；`groupEndpointProvider`；`KvCliTodoConst.prefActiveGroup == 'kvtodo-default-group'`

- [ ] **Step 1: 新建 `lib/api/goframe/group/group_endpoint.dart`**

```dart
import '../../api_client.dart';
import '../../api_response.dart';

/// 工作空间（group）端点 —— 查询我的工作空间。
class GroupEndpoint {
  final ApiClient _client;

  GroupEndpoint(this._client);

  /// 我的工作空间列表（我创建 + 我加入）。返回 ApiResponse，调用方判 isSuccess。
  Future<ApiResponse<List<KvGroup>>> list() => _client.request<List<KvGroup>>(
        method: 'GET',
        path: '/api/v1/groups',
        fromJson: (json) => (json['groups'] as List<dynamic>? ?? const [])
            .map((e) => KvGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 工作空间模型。
class KvGroup {
  final int id;
  final String name;
  final String description;
  final String myRole;
  final int memberCount;

  const KvGroup({
    required this.id,
    required this.name,
    this.description = '',
    this.myRole = '',
    this.memberCount = 0,
  });

  factory KvGroup.fromJson(Map<String, dynamic> json) => KvGroup(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        myRole: json['myRole'] as String? ?? '',
        memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      );
}
```

- [ ] **Step 2: `KvEndpoint` 4 方法加可选 `groupId`**

`lib/api/goframe/kv/kv_endpoint.dart` 改为（注意 `KvOps` 接口**不动**）：
```dart
  @override
  Future<ApiResponse<KvItem?>> get(String key, {int? groupId}) =>
      _client.request<KvItem>(
        method: 'GET',
        path: '/api/v1/kv/$key${_gidQuery(groupId, hasQuery: false)}',
        fromJson: (json) => KvItem.fromJson(json),
      );

  @override
  Future<ApiResponse<void>> set({
    required String key,
    required String value,
    int? ttl,
    int? groupId,
  }) =>
      _client.request<void>(
        method: 'POST',
        path: '/api/v1/kv',
        body: {
          'key': key,
          'value': value,
          if (ttl != null) 'ttl': ttl,
          if (groupId != null && groupId > 0) 'groupId': groupId,
        },
      );

  @override
  Future<ApiResponse<void>> delete(String key, {int? groupId}) =>
      _client.request<void>(
        method: 'DELETE',
        path: '/api/v1/kv/$key${_gidQuery(groupId, hasQuery: false)}',
      );

  @override
  Future<ApiResponse<KvListResult>> list({
    int limit = 50,
    int offset = 0,
    int? groupId,
  }) =>
      _client.request<KvListResult>(
        method: 'GET',
        path:
            '/api/v1/kv?limit=$limit&offset=$offset${_gidQuery(groupId, hasQuery: true)}',
        fromJson: (json) => KvListResult.fromJson(json),
      );

  /// groupId 有效(>0)时拼 query：已有 query 用 `&`，否则 `?`。
  String _gidQuery(int? groupId, {required bool hasQuery}) {
    if (groupId == null || groupId <= 0) return '';
    return '${hasQuery ? '&' : '?'}groupId=$groupId';
  }
```

- [ ] **Step 3: provider 注册**

`lib/api/providers/api_providers.dart`：加 import `'../goframe/group/group_endpoint.dart'`，并在 `kvEndpointProvider` 附近加：
```dart
final groupEndpointProvider = Provider<GroupEndpoint>((ref) {
  return GroupEndpoint(ref.watch(apiClientProvider));
});
```

- [ ] **Step 4: 常量**

`lib/lab/demos/kvcli_todo/const_kvcli_todo.dart` 追加（`keyDoneColdPrefix` 之后）：
```dart
  /// 激活工作空间持久化 key（SharedPreferences，int；0=服务端默认组）
  static const String prefActiveGroup = 'kvtodo-default-group';
```

- [ ] **Step 5: 编译检查**

Run: `flutter analyze lib/api/goframe/group/group_endpoint.dart lib/api/goframe/kv/kv_endpoint.dart lib/api/providers/api_providers.dart lib/lab/demos/kvcli_todo/const_kvcli_todo.dart`
Expected: 无 error（`KvOps` 实现类增补可选参数合法，`cloud_storage_sync` 不受影响）。

- [ ] **Step 6: 提交 + 推送**

```bash
git status
git add lib/api/goframe/group/group_endpoint.dart lib/api/goframe/kv/kv_endpoint.dart lib/api/providers/api_providers.dart lib/lab/demos/kvcli_todo/const_kvcli_todo.dart
git commit -m "feat(api): GroupEndpoint + KvEndpoint 可选 groupId 注入 + kvtodo-default-group 常量"
git push
```

---

## Task 2: 激活组 ref 存储 + demo 注入

**Files:**
- Create: `lib/lab/demos/kvcli_todo/active_group_provider.dart`
- Modify: `lib/lab/demos/kvcli_todo_demo.dart`（`ConsumerStatefulWidget` + `_gid` 三元 + `_loadAll` + helpers 带 groupId + 两个 delete）

**Interfaces:**
- Produces: `activeGroupProvider`（`StateNotifierProvider<ActiveGroupNotifier, int>`，0=默认组）；`ActiveGroupNotifier.load()/set(int)`；demo 内 `int? get _gid`
- Consumes: Task 1 的 `KvCliTodoConst.prefActiveGroup`、`GroupEndpoint.list()`、`KvEndpoint.*({int? groupId})`

- [ ] **Step 1: 新建 `lib/lab/demos/kvcli_todo/active_group_provider.dart`**

```dart
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
```

- [ ] **Step 2: demo 改为 ConsumerStatefulWidget + 接 groups 端点**

`lib/lab/demos/kvcli_todo_demo.dart`：

imports 追加：
```dart
import '../../api/goframe/group/group_endpoint.dart';
import 'kvcli_todo/active_group_provider.dart';
```

`buildPage` 的 Consumer 里同时解析 kv + groups，并传给页面：
```dart
      return Consumer(
        builder: (context, ref, _) {
          final KvEndpoint kv;
          final GroupEndpoint groups;
          try {
            kv = ref.watch(kvEndpointProvider);
            groups = ref.watch(groupEndpointProvider);
          } catch (e) {
            return Scaffold(
              body: Center(child: Text('KV 端点初始化失败：${_errMsg(e)}')),
            );
          }
          return _KvcliTodoDemoPage(kv: kv, groups: groups);
        },
      );
```

`_KvcliTodoDemoPage`：`StatefulWidget` → `ConsumerStatefulWidget`；加 `final GroupEndpoint groups;`；State 基类改 `ConsumerState<_KvcliTodoDemoPage>`（拿到 `ref`）。

state 新增字段：
```dart
  List<KvGroup> _groups = const [];
```

- [ ] **Step 3: `_gid` 三元 getter + `_loadAll` 载入激活组**

在 state 里加：
```dart
  /// 激活组注入 KV 的三元值：0 → null（后端回落默认组），>0 → 原值。
  int? get _gid {
    final gid = ref.read(activeGroupProvider);
    return gid == 0 ? null : gid;
  }
```

`_loadAll()` 替换为（先确保激活组载入，再并行拉数据）：
```dart
  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await ref.read(activeGroupProvider.notifier).load(); // 确保激活组已载入
    try {
      final groupRes = await widget.groups.list();
      final open = await _readTasks(KvCliTodoConst.keyOpen);
      final done = await _readTasks(KvCliTodoConst.keyDone);
      final topics = await _readTopics();
      if (!mounted) return;
      setState(() {
        _groups = (groupRes.isSuccess && groupRes.data != null)
            ? groupRes.data!
            : const [];
        _open = open;
        _done = done;
        _topics = topics;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('读取失败：${_errMsg(e)}');
    }
  }
```

- [ ] **Step 4: 读写 helper 统一带 groupId**

`lib/lab/demos/kvcli_todo_demo.dart`：
```dart
  Future<List<KvTask>> _readTasks(String key) async {
    final res = await widget.kv.get(key, groupId: _gid);
    if (!res.isSuccess || res.data == null) return const <KvTask>[];
    return KvTask.parseList(res.data!.value);
  }

  Future<List<String>> _readTopics() async {
    final res = await widget.kv.get(KvCliTodoConst.keyTopics, groupId: _gid);
    if (!res.isSuccess || res.data == null) return const <String>[];
    final raw = res.data!.value.trim();
    if (raw.isEmpty) return const <String>[];
    try {
      final list = (jsonDecode(raw) as List).cast<String>();
      return list.where((s) => s.trim().isNotEmpty).toList();
    } catch (_) {
      // 解析失败不阻塞 UI，留 debugPrint 排查
      debugPrint('kvcli_todo: parse topics failed, fallback to []');
      return const <String>[];
    }
  }

  Future<void> _writeKey(String key, String value) async {
    final res = await widget.kv.set(key: key, value: value, ttl: 0, groupId: _gid);
    if (!res.isSuccess) {
      throw Exception('写 $key 失败: code=${res.code} ${res.message}');
    }
  }
```
（`_saveTasks`/`_saveTopics` 走 `_writeKey`，自动带上；无需改。）

两处显式 delete 加 groupId：
```dart
  // _clearAll 内
      await widget.kv.delete(KvCliTodoConst.keyOpen, groupId: _gid);
      await widget.kv.delete(KvCliTodoConst.keyDone, groupId: _gid);
```
```dart
  // _clearDoneToCold 内
      await widget.kv.delete(KvCliTodoConst.keyDone, groupId: _gid);
```

- [ ] **Step 5: 编译检查**

Run: `flutter analyze lib/lab/demos/kvcli_todo/active_group_provider.dart lib/lab/demos/kvcli_todo_demo.dart`
Expected: 无 error。

- [ ] **Step 6: 提交 + 推送**

```bash
git status
git add lib/lab/demos/kvcli_todo/active_group_provider.dart lib/lab/demos/kvcli_todo_demo.dart
git commit -m "feat(lab/kvcli-todo): 激活工作空间 ref 存储 + KV 三元注入 groupId"
git push
```

---

## Task 3: demo UI — AppBar 工作空间 chip + 选择 bottom sheet

**Files:**
- Modify: `lib/lab/demos/kvcli_todo_demo.dart`（AppBar title、`_groupLabel`、`_openWorkspaceSheet`、`_workspaceTile`、`_setActiveGroup`）

**Interfaces:**
- Consumes: Task 2 的 `ref`/`_groups`、`activeGroupProvider(.notifier)`；`_loadAll()`

- [ ] **Step 1: `_groupLabel` helper**

```dart
  /// 激活组显示名：0→默认；命中 _groups 用其 name；找不到→#id。
  String _groupLabel(int gid) {
    if (gid == 0) return '默认';
    for (final g in _groups) {
      if (g.id == gid) return g.name;
    }
    return '#$gid';
  }
```

- [ ] **Step 2: AppBar title 加工作空间 chip**

`build` 里 `final scheme = Theme.of(context).colorScheme;` 之后加 `final gid = ref.watch(activeGroupProvider);`；`title:` 改为：
```dart
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('KV 清单'),
          const SizedBox(width: 10),
          InkWell(
            onTap: _openWorkspaceSheet,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspaces_outlined,
                      size: 14, color: scheme.primary),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      '工作空间 · ${_groupLabel(gid)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: scheme.primary),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down,
                      size: 16, color: scheme.primary),
                ],
              ),
            ),
          ),
        ],
      ),
```

- [ ] **Step 3: workspace bottom sheet + 切换**

```dart
  Future<void> _openWorkspaceSheet() async {
    final gid = ref.read(activeGroupProvider);
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        final scheme = Theme.of(sheetCtx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('工作空间',
                    style: Theme.of(sheetCtx).textTheme.titleMedium),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _workspaceTile(
                        sheetCtx,
                        scheme,
                        id: 0,
                        name: '默认组（服务端）',
                        role: '',
                        active: gid == 0,
                      ),
                      for (final grp in _groups)
                        _workspaceTile(
                          sheetCtx,
                          scheme,
                          id: grp.id,
                          name: grp.name,
                          role: grp.myRole,
                          active: gid == grp.id,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || selected == gid) return;
    await _setActiveGroup(selected);
  }

  Widget _workspaceTile(
    BuildContext ctx,
    ColorScheme scheme, {
    required int id,
    required String name,
    required String role,
    required bool active,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(
        active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 18,
        color: active ? scheme.primary : scheme.outline,
      ),
      title: Text(name),
      subtitle: role.isNotEmpty
          ? Text(role, style: TextStyle(fontSize: 11, color: scheme.outline))
          : null,
      trailing: active
          ? Text('当前',
              style: TextStyle(fontSize: 11, color: scheme.primary))
          : null,
      onTap: () => Navigator.pop(ctx, id),
    );
  }

  Future<void> _setActiveGroup(int id) async {
    await ref.read(activeGroupProvider.notifier).set(id);
    if (!mounted) return;
    await _loadAll();
  }
```

- [ ] **Step 4: 编译检查**

Run: `flutter analyze lib/lab/demos/kvcli_todo_demo.dart`
Expected: 无 error（`ref.watch` 在 `build` 内调用；chip 无 Flexible 溢出风险——用 ConstrainedBox 限宽）。

- [ ] **Step 5: 提交 + 推送**

```bash
git status
git add lib/lab/demos/kvcli_todo_demo.dart
git commit -m "feat(lab/kvcli-todo): AppBar 工作空间选择 + bottom sheet 切换"
git push
```

---

## 手动 E2E（提交后真机/网页验证）

1. 进 KV 清单 → AppBar 显示「工作空间 · 默认」。
2. 打开 sheet → 列「默认组（服务端）」+ 我的工作空间（含个人空间，带 myRole 标签）；当前项 ◉ + 「当前」。
3. 选一个工作空间 → 列表切为该组数据（空的显示暂无待办）；重启 app 保持选中（`kvtodo-default-group`）。
4. 切回「默认组（服务端）」→ 原数据回来。
5. 各写操作（添加/完成/克隆/清理冷数据/快捷 topic）落在当前组。
6. cloud_storage_sync 等未受影响（不传 groupId，走默认组）。

## 参考

- 设计：`docs/superpowers/specs/2026-08-08-kvcli-group-design.md`
- kvcli 参考：`D:/code/a_go/leaning/dev_ctr_hello/lab/kvcli/cmd/group.go`、`internal/api/client.go`
