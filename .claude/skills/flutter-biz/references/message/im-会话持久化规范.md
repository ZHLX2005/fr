# IM 会话持久化规范

> 适用范围：`lib/screens/chat/home_page.dart` 下的所有 chat 入口（当前 4 个：Agent / Format / 小票 / 小助手），以及未来水平扩展的任何新入口。
>
> 核心要求：**每个 chat 入口的整个会话必须持久化** —— 不是单条消息的临时 io，而是完整会话流（用户消息 + AI 返回 + 交互确认结果）重启后可完整恢复。

## 1. 规范总则

### 1.1 会话域定义

一个 chat 入口 = 一个会话域（session domain）。会话域内所有消息按时间序构成完整会话，持久化单位是**整个会话列表**，不是单条消息。

```
home_page.dart (_entries)          ← 入口注册表（水平扩展点）
  ├─ Agent        → AgentChatProvider        → prefs: agent_chat_messages
  ├─ Format       → MessagePanelController   → (待整改，见 §4)
  ├─ 小票         → ReceiptOcrHistoryStore   → prefs: receipt_ocr_history + docs 图片
  └─ 小助手       → SystemEventsController   → prefs: system_events_controller.v1
```

**水平扩展约定**：新增 chat 入口 = 在 `_entries` 追加一项 `AssistantEntry` + 一个会话域实现（Provider/Controller + Store），Store 必须实现 §2 的存储契约。禁止出现"纯内存会话"的入口。

### 1.2 三条铁律

1. **整会话保存**：会话列表任何变更（append / 状态转换 / 清空）后回写持久层。用户消息和 AI 返回消息成对保存。
2. **状态转换必须记录**：确认型消息（ask/selection/小票行项确认）在用户确认后，把确认结果回写持久层，重进页面时渲染锁定态，不能回到未确认状态。
3. **数据类自带编解码**：每个会话数据类实现 `toJson()` / `fromJson()` + `encodeList()` / `decodeList()`（参考 `ReceiptOcrHistory`），不用 Hive TypeAdapter（CI 有 part 文件构建失败前科，见 flutter-work-flow 技能 ref）。

## 2. 存储契约 SOP（新入口接入）

### 2.1 key 命名

```
SharedPreferences key: <domain>_history 或 <domain>.v1
版本化示例：'system_events_controller.v1'
```

同域多 key 时加后缀：`system_events_controller.read_index.v1`。

### 2.2 Store 最小接口

```dart
abstract class SessionStore<T> {
  Future<List<T>> load();              // 启动恢复；解析失败返回 []，不抛异常
  Future<void> add(T entry);           // append 后回写全量列表
  Future<void> update(String id, T entry); // 状态转换后按 id 回写（§3）
  Future<void> clear();                // 仅用户主动清空触发
}
```

实现要点（exemplar：`lib/core/ai_chat/receipt_ocr/receipt_ocr_history_store.dart`）：

- **上限截断**：`maxEntries = 200`，超出 FIFO 删最旧；关联资源（图片文件）随截断一起删
- **孤儿过滤**：load 时过滤掉关联文件已不存在的记录（图片被系统清理）
- **文件名不存绝对路径**：只存文件名，load 时经 `resolveImagePath()` 现算绝对路径，避免重启后路径漂移
- **大对象外置**：图片等二进制放 `getApplicationDocumentsDirectory()/<domain>/`，prefs 只存索引

### 2.3 竞态保护（恢复 vs 启动钩子先写入）

`main()` 中启动钩子（crash 摄入、APK 自动检查）可能在 `restore()` 完成前就 `append()`。恢复时把磁盘旧事件插到已有新事件**前面**，两侧都不丢。幂等守卫：

```dart
Future<void> restore() => _restoreFuture ??= _doRestore();
```

（完整实现参考 `SystemEventsController.restore()`，commit `74fdc6ce`）

### 2.4 Controller 挂载模式

GetIt 单例 + `ChangeNotifier`；写操作（append/markAllRead/clear）末尾 `_schedulePersist()`（fire-and-forget，失败静默）；main() 在 `registerMessageStrategies()` 之后 `unawaited(restore())`。

## 3. 确认型消息的状态转换记录

### 3.1 问题

小票 OCR 返回的卡片带行项确认功能（记录/拒绝每行）。如果确认状态只存 UI State（`_isFixed`），重启后卡片回到未确认态，用户的操作丢失。

### 3.2 三步契约（exemplar：小票行项确认）

```
① 内存更新    LineItem.confirmState = accepted/rejected   （不可变对象 → copyWith/重建）
② 回写持久层  ReceiptOcrHistoryStore.updateItems(historyId, items)  → 按 id 找到记录，重建整个 ReceiptOcrHistory 替换，prefs.setString 全量回写
③ 重建渲染    重进页面 → load() → ReceiptOcrMessageData(result: h.result) 卡片从持久化 result 读确认态 → 锁定 UI
```

关键设计：

- **数据类不可变，状态在数据里**：`LineItem` 的确认结果存在持久化模型中，UI 只是渲染投影。**不**依赖 strategy widget 的内部 `setState`。
- **卡片携带稳定 id**：`ReceiptOcrMessageData(result, historyId)` —— `historyId` 是回写持久层的寻址键。
- **找不到 id 静默跳过**：历史被清空时 `updateItems` 直接 return，不抛异常。

### 3.3 推广到 ask/selection

`flutter-message-workflow` 主文档的 Ask/Selection 模式用 `_isFixed` 内部 State 锁定 UI —— 那是**演示态**。落在真实会话入口时，必须按 §3.2 三步契约升级：确认结果写进会话模型 → 回写 Store → 重进页面渲染锁定态。

## 4. 现状矩阵与整改指引

| 入口   | 会话存储                                  | 持久化                          | 状态转换记录             | 合规        |
| ------ | ----------------------------------------- | ------------------------------- | ------------------------ | ----------- |
| Agent  | `AgentChatProvider`                     | ✅ prefs 全量会话               | —（纯文本会话无确认卡） | ✅          |
| Format | `MessagePanelController`                | ❌ 纯内存，重启即空             | ❌                       | ⚠️ 待整改 |
| 小票   | `_entries` + `ReceiptOcrHistoryStore` | ✅ 会话+图片                    | ✅`updateItems` 回写   | ✅ exemplar |
| 小助手 | `SystemEventsController`                | ✅ prefs（v1, 2026-08-18 修复） | —（只读事件流）         | ✅          |

**Format 入口整改方向**：`MessagePanelController`（`lib/services/message_strategy/panel/message_panel_controller.dart`）加持久化 —— 消息数据走 `data.toJson()` 需 `IMessageData` 补 `toJson`/`fromJson` 注册表（可挂在 MessageWidgetFactory 上：每 strategy 声明编解码）。状态转换（登录/注册流）按 §3.2 处理。

## 5. 新入口上线自查表

- [ ] Store 实现最小接口（load/add/update/clear），解析失败返回 []
- [ ] prefs key 按命名规范，必要时版本化
- [ ] 上限 200 条截断 + 关联资源清理
- [ ] 大二进制外置 docs 目录，只存文件名
- [ ] restore() 幂等 + 启动钩子竞态保护（§2.3）
- [ ] 确认型消息三步契约（§3.2），确认结果在持久化模型里
- [ ] 清空仅用户主动触发（确认对话框）
- [ ] `flutter analyze` 0 error 后提交，CI 构建 APK 验证
