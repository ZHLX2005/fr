# fr 主题任务意图文档（taskget 领取）

> 领取时间：2026-08-07 ｜ 来源：kvcli todo（topic=`fr`）｜ 消费者：agent
> 状态：意图已对齐，按确认顺序解决

## 优先级（用户确认）

1. **簇 C — kv 清单功能**（任务 6 + 9）— **范围=App 内 kvcli_todo_demo 预览**
2. **簇 A — 俄罗斯方块同步 bug**（任务 1）
3. **簇 D(部分) — 小票状态添加/持久化 bug**（任务 8）
4. **簇 B — pigment 启动按钮全白**（任务 5）

任务 10（小票提示词/结构对齐）用户未排优先级 → **挂起待定**。

---

## 簇 C：kv 清单功能增强（App 内 demo）

**涉及文件**：`lib/lab/demos/kvcli_todo_demo.dart`（单文件 demo，≈673 行）
**后端链路**：POST/GET/DELETE `/api/v1/kv`，value=`Task[]` / `String[]` JSON
**原则（用户确认）**：**KV 只提供快照存储**；demo 不引入后端业务逻辑，每个实体 = 一把 KV key 的快照读写。
**最终范围**：task 完整 CRUD；tag(topic) 仅添加+删除；prompt 不做 CRUD。

### KV 命名空间（三把 key，全部快照读写）

| key | value 形态 | 实体 | 操作 |
|---|---|---|---|
| `todo:open` | `Task[]` JSON | 待办任务 | 完整 CRUD |
| `todo:done` | `Task[]` JSON | 已完成任务 | 完整 CRUD |
| `todo:topics` | `String[]` JSON | 快捷 topic（tag） | 仅添加 + 删除 |

### 任务 6：添加快捷 topic / 删除快捷 topic（tag），避免无限膨胀

- 现状：`_TopicChip` 只读，`_recentTopics()` 按任务主题频次自动取前 8，无法增删。
- 改为：**快捷 topic 显式管理**，渲染自 `todo:topics` 快照：
  - **添加**：输入/保存一个 topic 到 `todo:topics`；
  - **删除**：chip 上 ✕ 删除，持久化到 KV；
  - 不再从任务主题自动派生（解决「无限膨胀」）。
- 点击 chip 仍回填主题输入框（保留现有便捷行为）。

### 任务 9：task 完整 CRUD

- 现状：仅 add / done / clearAll，无编辑、无单条删除。
- 新增：
  - **edit**：open 任务改 text/topic；done 任务改 text/note。弹 dialog，保存后 `_writeKey` 重写整把 key。
  - **delete**：单条删除（open/done 均可），带确认。
  - done 保留（移动 open→done + note）。
- 实现要点：后端无单条更新 API，靠 **重写整把 key** 实现（读数组 → 定位 id → 替换/移除 → `_writeKey`）。
- 验收：编辑任务文本/主题 → 界面即时更新 + 刷新后保持；open 编辑不改 id / createdAt；单条删除不误删其他任务。

---

## 簇 A：俄罗斯方块双人同步 bug（todo id 1）

**原始**：俄罗斯方块存在bug，无法同步，两个人连接会变成0，突然看不见对方数据
**涉及**：`lib/lab/demos/tetris_lua_demo.dart`、`lib/lab/demos/tetris_lua/`（engine/board/constants/widgets/tetris_script）
**方法**：按 superpowers:systematic-debugging 走，先复现/看日志定位「连接归零 + 对端不可见」发生在消息同步层还是快照层（参考 `.claude/skills/relay-lua-state-machine` 的事件 vs 快照协议）。
**验收**：双人建立连接后计数不归零，对端数据持续可见。

---

## 簇 D：小票 OCR（todo id 8）

**原始**：小票ocr消息，已经记录的状态没有记录，每次重新进入页面，显示的列表都是等待记录状态
**涉及**：receipt_ocr 相关（近期 commit `43e88a8f fix(receipt_ocr): PickerSheet 选中现有主题后没 appendRow (UI 与 Hive 不同步)` 同域）
**期望**：已「记录」的消息状态持久化到 Hive，重进页面仍显示已记录；修复 UI 状态与存储不同步。

---

## 簇 B：pigment 启动按钮全白（todo id 5）

**原始**：pigment悬浮板的启动按钮，变成全白了
**涉及**：`lib/lab/demos/pigment_palette_demo.dart`
**期望**：启动按钮恢复正常配色（疑似样式回归 / 主题色丢失）。

---

## 待定

- **任务 10**（小票提示词/结构对齐比价计算器）：未排优先级，等用户指示。
