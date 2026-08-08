# kv 清单工作空间（group）支持 — 设计

> 日期：2026-08-08。需求来源：kv 清单（`lib/lab/demos/kvcli_todo_demo.dart`）需支持设置/查询/选择工作空间，模仿 Go 端 kvcli 的 group 方案。
> 范围（用户拍板）：**仅 list + select**（查询工作空间 + 切换激活组，本地持久化）；不做 create / show 默认组 / 不切服务端 default_group_id。

## 背景与参考

- **kvcli（Go）group 方案**：`group list`（GET /api/v1/groups）、`group use <id>`（激活组存本地 config，0=回默认组，切换前校验成员）、`group show`、`group create`。激活组 `Client.GroupID` 在 `Request()` 里自动注入所有 KV 请求（GET/DELETE→query、POST/PUT/PATCH→body）。
- **后端**：`47.110.80.47:8988`（与 kvcli、Flutter `ApiConfig.production()` 同源）。KV 已切 Postgres + `kv_items.group_id`（UNIQUE(group_id, key)），不传 groupId 回落 `users.default_group_id`。group 端点：GET `/api/v1/groups`（我创建+加入）、POST `/api/v1/groups`。
- **Flutter 现状**：`KvEndpoint`（`lib/api/goframe/kv/kv_endpoint.dart`）的 get/set/delete/list **均无 groupId**；无 group endpoint；provider 模式（`apiClientProvider` → 各 endpoint provider）已建立；本地持久化惯例用 SharedPreferences（clock 同款）。

## 目标

kv 清单页面支持：查询我的工作空间、切换当前激活的工作空间（0=服务端默认组），激活组本地持久化，所有 KV 操作自动落在该组命名空间（每组的 `todo:open`/`todo:done`/`todo:topics` 相互隔离）。

## 组件设计

### 1. GroupEndpoint（新文件 `lib/api/goframe/group/group_endpoint.dart`）

- 模型 `KvGroup`：
  - `int id`（JSON `id`）
  - `String name`
  - `String description`
  - `String myRole`（owner/admin/writer/reader）
  - `int memberCount`（JSON `memberCount`）
  - `fromJson` 各字段带默认兜底（数值 0、字符串 ''）。
- `GroupEndpoint.list()` → `Future<ApiResponse<List<KvGroup>>>`：
  - `GET /api/v1/groups`，响应 `data.groups`（数组）。`data == null` / `groups` 缺失返回 `const []`。
  - 沿 `KvEndpoint` 风格：**不抛异常**，返回 `ApiResponse`，由调用方判 `isSuccess`。
- provider：`api_providers.dart` 加
  ```dart
  final groupEndpointProvider = Provider<GroupEndpoint>((ref) {
    return GroupEndpoint(ref.watch(apiClientProvider));
  });
  ```

### 2. KvEndpoint 加可选 groupId（改 `lib/api/goframe/kv/kv_endpoint.dart`）

给 4 个方法加**可选** `int? groupId` 参数，`null` 或 `0` 时不携带（后端回落默认组，与 kvcli `GroupID > 0` 才注入一致）：

- `get(String key, {int? groupId})` → path `/api/v1/kv/$key`；groupId 有效时拼 `?groupId=N`（已有 query 则 `&`）。
- `delete(String key, {int? groupId})` → 同 GET。
- `list({int limit = 50, int offset = 0, int? groupId})` → path `/api/v1/kv?limit=&offset=`；追加 `&groupId=N`。
- `set({required String key, required String value, int? ttl, int? groupId})` → body 加 `'groupId': groupId`（有效时）。

既有调用方（`cloud_storage_sync.dart` 走 `KvOps` 接口）不传即行为不变——**向后兼容**。

### 3. demo 状态与注入（改 `lib/lab/demos/kvcli_todo_demo.dart`）

- 状态：`int _activeGroupId = 0`；`List<KvGroup> _groups = const []`。
- `initState` 里从 SharedPreferences 读激活组（key 常量见下），失败回落 0。
- `_loadAll()` 并行拉：`groupEndpoint.list()` → `_groups`；`_readTasks(open)`、`_readTasks(done)`、`_readTopics()` —— 三个读都带当前 `groupId`。
  - groups 拉取失败：不阻塞，`_groups` 保持空，AppBar 回落「工作空间」，toast 提示。
- 所有写操作统一传 `groupId: _activeGroupId == 0 ? null : _activeGroupId`：
  - `_add` / `_markDone` / `_editTask` / `_deleteTask` / `_cloneTask` / `_clearDoneToCold` / `_clearAll` / `_addTopic` / `_deleteTopic`。
  - 集中：在 `_readTasks`/`_saveTasks`/`_saveTopics`/`_writeKey` 内部传，避免散落。

### 4. 常量（改 `lib/lab/demos/kvcli_todo/const_kvcli_todo.dart`）

```dart
/// 激活工作空间持久化 key（SharedPreferences，int；0=服务端默认组）
static const String prefActiveGroup = 'kvcli_todo_active_group';
```

### 5. UI（AppBar 入口）

- AppBar 标题改 `Row`：`Text('KV 清单')` + 间距 + 工作空间 chip：
  - 显示逻辑：`_activeGroupId == 0` → 「工作空间 · 默认」；`>0` → 在 `_groups` 按 id 找名，找到显示「工作空间 · <name>」，找不到「工作空间 · #<id>」；`_groups` 空且 >0 → 「工作空间 · #<id>」。
  - chip 带 `arrow_drop_down` 图标，`onTap → _openWorkspaceSheet()`。
- `_openWorkspaceSheet()` → `showModalBottomSheet`：
  - 第一行固定「默认组（服务端）」（id=0），激活时 ◉ 高亮。
  - 之后每项 `_groups` 的 group：`name` + `myRole` 标签；激活 ◉ / 未激活 ○。
  - 点击行 → `prefs.setInt(prefActiveGroup, id)` → `setState(_activeGroupId = id)` → `_loadAll()`（该组数据立即可见）。
  - 空态：`_groups` 为空只显示「默认组（服务端）」一行。
  - 切换失败（prefs 写失败）：toast，不改变当前状态。

## 数据流

```
初始化: prefs.read(prefActiveGroup) → _activeGroupId
        _loadAll(): GET /groups + GET kv(open/done/topics, groupId=_activeGroupId)
选空间: sheet 选中 id → prefs.write → setState(_activeGroupId) → _loadAll()
写操作: 全部带 groupId → 落在该组命名空间（与 kvcli 注入语义一致）
```

## 错误处理

| 场景 | 行为 |
|---|---|
| groups 拉取失败 | `_groups` 空，AppBar 显示「工作空间 ▾」，toast，默认组可用 |
| prefs 读写失败 | 忽略/回落默认组 |
| 切换后 KV 无权限 / key 不存在 | 走现有 `_toast` 机制 |
| groupId 非法（不在 groups） | 持久化的 id 找不到 → AppBar 显示「空间 #id」，仍可打开 sheet 重选 |

## 明确不做（scope）

- **只有 kv 清单（demo）传 groupId**；其他用 KV 的地方（cloud_storage_sync 等）一律不传，走服务端默认组——`KvEndpoint` 的 `groupId` 保持可选、缺省即默认。
- 不建工作空间（create）——用户拍板仅 list + select。
- 不显示服务端默认组的**真实组名**（不做 `GET /user/default-group`）；UI 上「默认」即表示服务端默认组。group 列表来自 `GET /groups`（含个人空间）。
- 不切服务端 `default_group_id`（与 kvcli 一致，仅本地激活）。

## 验证

- `flutter analyze`：改动文件（`group_endpoint.dart` 新、`kv_endpoint.dart`、`kvcli_todo_demo.dart`、`const_kvcli_todo.dart`、`api_providers.dart`）无 error。
- 手动 E2E：
  1. 进 KV 清单 → AppBar 显示「工作空间 · 默认」。
  2. 打开 sheet → 列默认组 + 我的工作空间（含个人空间）；选一个 → 列表变为该组数据（空的显示暂无待办）。
  3. 切回默认 → 原数据回来。
  4. 重启 app → 保持上次选中。
  5. 各写操作（添加/完成/克隆/清理冷数据/快捷 topic）落到当前组。
- 不做单元测试（UI + 网络依赖，与同批修复一致）。

## 参考文件

- kvcli 参考：`D:/code/a_go/leaning/dev_ctr_hello/lab/kvcli/cmd/group.go`、`internal/api/client.go`。
- 后端 group API 契约：`dev_ctr_hello/.claude/skills/user-kv-invitecode/SKILL.md`（GET/POST `/api/v1/groups`，KV 带 groupId）。
