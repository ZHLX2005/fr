# Ba02 — IM 会话持久化规范

> **适用范围**：`lib/screens/chat/home_page.dart` 下登记的真实 chat 入口，以及未来新增的水平扩展入口。当前入口以代码为准（Agent、Format、小票 OCR、系统事件、pi 等）。
>
> 这是**新增/接入会话的规范**，不是“所有现存入口已全部达标”的现状声明。现存 gap 明确写在 §4。

## 1. 会话域定义

一个 chat 入口 = 一个会话域（session domain）。持久化单位是整个会话列表（用户消息 + AI 返回 + 确认状态），不是单条消息的临时对象。

```text
lib/screens/chat/home_page.dart（entries = 水平扩展点）
  Agent    → AgentChatProvider      → prefs: agent_chat_messages
  Format   → MessagePanelController → 纯内存（已知 gap，见 §4）
  小票 OCR → ReceiptOcrHistoryStore → prefs: receipt_ocr_history + docs 图片
  系统事件 → SystemEventsController → prefs: system_events_controller.v1
  pi       → PiChatMessageRepository（Hive typed box）→ lib/core/ai_chat/pi/
```

不同入口可用不同存储后端：prefs（简单 JSON 列表）或 Hive（模型有 typed repository，pi 就是现行例子）。历史文档“禁用 Hive TypeAdapter”来自旧 part-file CI 问题；当前项目已回到 `hive_generator` + build_runner，新会话若用 Hive 按 D 序列规则执行。

## 2. 三条铁律

1. **整会话保存**：会话列表任何变更（append / 状态转换 / 清空）后回写持久层；用户与 AI 消息成对保存。
2. **状态转换必须记录**：确认型消息（ask/selection/行项确认）在用户确认后把结果写进会话模型并回写持久层；重进页面渲染锁定态，不能回到未确认。
3. **编解码与截断是 Store 的责任**：JSON 会话实现 `toJson/fromJson` 与 list 编解码；上限截断、孤儿过滤和资源外置见 §3。

## 3. 存储契约（新入口接入）

### 3.1 键名

- SharedPreferences 会话 key：`<domain>_history` 或版本化 `<domain>.v1`；同域多 key 加子后缀。
- Hive 会话按 D 序列：模型 `@HiveType(typeId: HiveTypeIds.xxx)`，repository 实现 `HiveRepository`，初始化注册 `BoxDescriptor`。

### 3.2 最小 Store 契约（目标接口）

```dart
abstract class SessionStore<T> {
  Future<List<T>> load();                 // 启动恢复；解析失败返回 []，不抛
  Future<void> add(T entry);              // append 后回写全量列表
  Future<void> update(String id, T entry); // 状态转换后按 id 回写
  Future<void> clear();                   // 仅用户主动清空触发
}
```

> `SessionStore` 是新增入口的**设计契约**，当前仓库没有统一基类实现；每个入口按各自 Store 落实该语义，不在 demo/页面散写解析。

实现要点（参照 `lib/core/ai_chat/receipt_ocr/receipt_ocr_history_store.dart`）：

- 上限截断（如 200 条 FIFO），关联资源（图片文件）随记录一起删除。
- load 时过滤关联文件缺失的记录（孤儿过滤）。
- 不持久化绝对路径；只存文件名，读取时用当前 app 目录拼路径。
- 大二进制外置到 `getApplicationDocumentsDirectory()/<domain>/`，索引只存轻量元数据。
- 恢复幂等：`Future<void> restore() => _restoreFuture ??= _doRestore();`，启动钩子可能在恢复完成前 append，恢复时把磁盘旧记录插到新记录之前。

### 3.3 控制器挂载

GetIt 单例 + `ChangeNotifier`；写操作后调度持久化（fire-and-forget 需记录失败日志/提示策略）；`main()` 初始化阶段 `unawaited(restore())`，不要等首帧页面。

## 4. 确认型消息三步契约

以小票行项确认为 exemplar：

```text
① 内存更新    LineItem.confirmState = accepted/rejected（不可变对象重建）
② 回写持久层  ReceiptOcrHistoryStore.updateItems(historyId, items) → 全量替换并 setString
③ 恢复渲染    重进页面 → load() → 卡片从持久化 result 读确认态 → 锁定 UI
```

- 数据类不可变，确认状态存在持久化模型里；不依赖 strategy widget 内部 `setState`。
- 卡片携带稳定 `historyId` 作为回写寻址键。
- `updateItems` 找不到 id 时静默跳过（历史已被清空），不抛异常。

Ask/Selection 模式同理：演示态里的 `_isFixed` 必须升级为会话模型字段 + Store 回写。

## 5. 现状矩阵（2026-10 审计）

| 入口 | 存储 | 持久化 | 状态转换 | 结论 |
|---|---|---|---|---|
| Agent | `AgentChatProvider` | prefs 全量会话 | 纯文本会话无确认卡 | 达标 |
| Format | `MessagePanelController` | 纯内存，重启即空 | 未记录 | **已知 gap**；整改方向：给 `IMessageData` 补编解码注册表 + Store 回写 |
| 小票 OCR | `ReceiptOcrHistoryStore` | prefs + docs 图片 | `updateItems` 回写 | 达标 exemplar；注意识别失败轮次当前不入库（见 §6） |
| 系统事件 | `SystemEventsController` | prefs v1 | 只读事件流 | 达标 |
| pi | `PiChatMessageRepository` | Hive typed box + 服务端会话 | 流式消息落 Hive，失败标记后可恢复 | 达标；使用 D 序列 Hive 约定 |

## 6. 已知边界

- **识别失败轮次**：小票 OCR 当前只在识别成功后 `ReceiptOcrHistoryStore.add`；失败时的图片/错误卡片留在内存，重启后不恢复。需要“完整失败会话”的产品语义时，先扩展 OCR Store 或调整入口流程，不要宣称现状已覆盖。
- **Format 入口**：整改完成前，不要把“所有入口整会话持久化”写成既有事实。
- 修改任何入口的存储方式前，先读该入口当前实现与 D00/Hive 规则，避免双重事实源。

## 7. 新入口上线自查

- [ ] Store 实现最小契约语义（load/add/update/clear），解析失败返回空而不抛。
- [ ] prefs key/Hive box 遵循命名与 D 序列约定。
- [ ] 上限截断 + 关联资源清理 + 孤儿过滤。
- [ ] 大二进制外置，索引只存文件名。
- [ ] restore 幂等 + 启动钩子竞态保护。
- [ ] 确认型消息三步契约，确认结果在持久化模型里。
- [ ] 清空仅由用户主动触发（确认对话框）。
- [ ] `flutter analyze` 0 error；涉及 Hive 模型变更跑 build_runner；相关测试按项目流程执行。
