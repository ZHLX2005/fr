下面是把前两轮所有收敛点合并后的 **完整可落地方案** 。直接照这份做，已有 19 种 BlockType + AI Agent + 完善页面工作区都能安全演进。

---

# 基于 Block 树的 AI 编辑代理 · 完整方案 v1.0

## 0. 设计公理（不可妥协）

1. **同一数据模型贯穿全栈** ：AI 输出 Block 树，系统消费 Block 树，无格式转换层。
2. **AI 永远不真正删除存量内容** ：`DeleteBlock`(AI) → `ArchiveBlock`。
3. **AI 不直接修改"已完善"页面** ：仅生成 `SuggestionBlock`，由用户提升。
4. **每次 AI plan = 一次原子事务 = 一个 Undo 单元** 。
5. **AI 不可见即不可写** ：必须先 `read_subtree` 才能 `update`/`delete`。
6. **破坏面随距离衰减** ：默认最小权限，越靠近存量越严格。

---

## Part I · 数据模型层（基础设施）

### 1.1 BlockType 收敛（19 种）

| 类型                        | tag                   | 子节点         | content | data                                        |
| --------------------------- | --------------------- | -------------- | ------- | ------------------------------------------- |
| paragraph                   | `paragraph`         | ❌             | ✅      | —                                          |
| heading                     | `heading`           | ❌             | ✅      | `{level: 1..6}`                           |
| todo                        | `todo`              | ❌             | ✅      | `{checked: bool}`                         |
| toggle                      | `toggle`            | ✅             | ✅      | —                                          |
| bulletListItem              | `bullet_list_item`  | ✅             | ✅      | —                                          |
| orderedListItem             | `ordered_list_item` | ✅             | ✅      | —                                          |
| quote                       | `quote`             | ❌             | ✅      | —                                          |
| code                        | `code`              | ❌             | ✅      | `{language: string}`                      |
| divider                     | `divider`           | ❌             | ❌      | —                                          |
| callout                     | `callout`           | ❌             | ✅      | `{icon?, color?}`                         |
| image                       | `image`             | ❌             | ❌      | `{src, caption?, width?, height?}`        |
| embedCard                   | `embed_card`        | ❌             | ❌      | `{url}`                                   |
| bookmark                    | `bookmark`          | ❌             | ❌      | `{url, title?, desc?}`                    |
| equation                    | `equation`          | ❌             | ❌      | `{latex}`                                 |
| database                    | `database`          | ✅ databaseRow | ❌      | `{columns: [{id, name, type, options?}]}` |
| **databaseRow**⭐新增 | `database_row`      | ❌             | ❌      | `{<colId>: value}`                        |
| columnList                  | `column_list`       | ✅ column      | ❌      | —                                          |
| column                      | `column`            | ✅             | ❌      | `{ratio: double}`                         |
| syncedBlock                 | `synced_block`      | ❌             | ❌      | `{source_page_id, source_block_id}`       |
| **suggestion**⭐新增  | `suggestion`        | ❌             | ❌      | 见 §3.5                                    |

> 删除原稿的 `page` 类型。Page 是 Workspace 概念，不是 Block 类型。

### 1.2 Block 模型（扩展）

```dart
class Block {
  final String id;                          // UUID v4，工作区全局唯一
  final BlockType type;
  final RichText content;
  final List<Block> children;
  final BlockData data;
  final Map<String, dynamic> properties;    // 含 ai_locked / verification
  final DateTime createdAt;
  final DateTime updatedAt;
  
  /// 内容指纹：sha256(type + content + data) 的前 16 位
  /// 用于 §3.7 expected_hash 校验
  String get contentHash;
}
```

### 1.3 BlockTree（双索引，原方案保留）

`rootId = '__root__'`；`_blocks` / `_parents` / `_childrenOf` 三索引；变更流 `Stream<List<TreeChange>>`。

### 1.4 BlockOp（扩展可逆原语）

```
BlockOp (sealed)
├── InsertBlock        — 插入
├── UpdateBlock        — 更新（带 expectedHash）
├── DeleteBlock        — 真删除（用户操作专用，AI 不可调用）
├── ArchiveBlock ⭐    — 软删除：移到 __archive__ 隐藏 page，可还原
├── MoveBlock          — 移动
├── MergeBlocks        — 合并
├── SplitBlock         — 分割
└── NopOp              — 空操作
```

 **关键约束** ：`OperationHistory.applyBatch(ops, label)` 中若 `label.startsWith("ai:")`，所有 `DeleteBlock` 自动改写为 `ArchiveBlock`，由 `OpValidator` 强制执行。

### 1.5 OpValidator（新增 11 条规则）

| 规则                                    | 默认值                      | 触发拒绝               |
| --------------------------------------- | --------------------------- | ---------------------- |
| `maxOpsPerBatch`                      | 50 (AI) / 200 (user)        | 超限                   |
| `maxTreeDepthAfterOps`                | 12                          | 嵌套过深               |
| `maxBlockContentLength`               | 4000 字符                   | 超长                   |
| `maxChildrenPerBlock`                 | 500                         | 超广                   |
| `requireUniqueBlockIdAcrossWorkspace` | true                        | id 重复                |
| `forbidDeleteInAiBatch`               | true                        | AI 调 DeleteBlock      |
| `requireExpectedHashOnAiUpdate`       | true                        | AI Update 无 hash      |
| `requireReadBeforeWrite`              | true                        | 未读先写               |
| `forbidWriteOnAiLocked`               | true                        | 写带 `ai_locked`的块 |
| `forbidWriteOnLockedPage`             | true                        | 写 `locked`page      |
| `forbidEditOnCuratedPage`             | true (仅 `update/delete`) | curated page 上直接改  |

---

## Part II · Workspace 层

### 2.1 PageProtection（每页一级保护）

```dart
enum PageProtection {
  draft,      // 默认：AI 可全权
  curated,    // 已完善：AI 仅 suggest（产 SuggestionBlock）
  locked,     // 锁定：AI 只读
  archived,   // 归档：AI 不可见
}
```

 **自动升级提示** （不自动执行）：字数>2000 且 30天未AI编辑 / 被≥3 page 引用 / 用户 verified → 弹"建议提升为 curated"。 **永不自动降级** 。

### 2.2 PageModel

```dart
class PageModel {
  final String id;                          // UUID v4
  String title;
  String? icon;
  PageProtection protection;
  final BlockEditorController controller;   // 含 BlockTree + OpHistory
  DateTime createdAt;
  DateTime updatedAt;
  DateTime? lastAiEditAt;
  Set<String> tags;
}
```

### 2.3 WorkspaceManager

```dart
class WorkspaceManager {
  final Map<String, PageModel> pages;
  final List<String> pageOrder;             // 侧边栏排序
  String? activePageId;
  final WorkspaceAiPolicy policy;
  final PageSnapshotStore snapshots;
  final AiPlanLedger ledger;
  final UndoCoordinator undo;
  
  // 页面 CRUD
  PageModel createPage({String? title, PageProtection? protection});
  Future<void> deletePage(String id);       // 物理删除前先 archive 7 天
  Future<void> archivePage(String id);
  void switchPage(String id);
  void renamePage(String id, String title);
  void setProtection(String id, PageProtection p);
  
  // AI 相关
  PageModel get archivePage;                // __archive__ 隐藏页（存被 AI 归档的块）
  
  // 持久化（write-ahead）
  Future<void> persist();
}
```

### 2.4 持久化布局

```
storage/
├── workspace.json                    # {pageIds, pageOrder, activeId, policy}
├── pages/<pageId>.json               # PageModel + 全部 blocks
├── pages/<pageId>.history.bin        # OpHistory（崩溃恢复）
├── pages/<pageId>.snapshots/
│   ├── migration-baseline.json.zst   # 永不 evict
│   └── <timestamp>.json.zst          # 近 30 天 / 近 100 个，LRU
├── ai-plans/<planId>.json            # AiPlanLedger
└── __archive__/<blockId>.json        # 软删除块
```

 **Write-ahead 协议** ：内存指针只能在落盘成功后切换。

### 2.5 PageSnapshotStore

```dart
class PageSnapshotStore {
  Future<String> snapshot(String pageId, {String? label});  // 返回 snapshotId
  Future<List<SnapshotMeta>> list(String pageId);
  Future<void> restore(String pageId, String snapshotId);   // 作为新 op 进 history
  
  // 自动触发
  // - 每次 AI plan 前
  // - 用户连续编辑 5 分钟无 AI 介入
  // - 用户手动
}
```

### 2.6 AiPlanLedger

```dart
class AiPlanLedger {
  Future<void> record({
    required String planId,
    required DispatchPlan plan,
    required Map<String, String> beforeSnapshotIds,  // pageId → snapshotId
    required AiResponse response,
  });
  
  Future<List<PlanRecord>> recent({int limit = 20});
  Future<void> rollback(String planId);              // 用快照恢复 + 进 history
}
```

---

## Part III · AI 代理层

### 3.1 编辑模式（必选）

| 模式        | LLM 可用 tools                             | 默认                          |
| ----------- | ------------------------------------------ | ----------------------------- |
| `ask`     | read_block, read_subtree, search_blocks    | ✅                            |
| `append`  | ↑ + ai_append_blocks                      | 显式                          |
| `draft`   | ↑ + ai_create_page, ai_create_database    | 显式                          |
| `suggest` | ↑ + ai_suggest_edit（产 SuggestionBlock） | 显式                          |
| `edit`    | 全部（含 update/archive/move）             | 需解锁 + 当前 page 必须 draft |

UI：AI 输入条左侧模式徽章，curated/locked page 上 `edit` 不可选。

### 3.2 AiScopeFence

```dart
class AiScopeFence {
  final Set<String> allowedPageIds;         // 显式列出
  final Set<String>? allowedBlockIds;       // null = 整页；否则仅这些
  final BlockId? appendAnchor;
  final bool allowCreateNewBlocks;
  final bool allowModifyExistingBlocks;     // 默认 false
  final bool allowArchiveExistingBlocks;    // 默认 false
}
```

来源：用户选区 / 当前 page / 用户消息中 @ 提到的 page。**从不**默认包含未提及 page。

### 3.3 AiAction（顶层语义）

```dart
sealed class AiAction { RiskLevel get risk; }

class CreatePageAction extends AiAction {
  final String? clientId;                   // LLM 生成，用于关联后续 op
  final String title;
  final List<BlockJson> blocks;
  final PageProtection initialProtection;   // 默认 draft
}

class CreateDatabaseAction extends AiAction {
  final String targetPageId;
  final BlockId? afterAnchor;
  final String title;
  final List<DatabaseColumn> columns;       // 必须含稳定 id
  final List<Map<String, dynamic>> rows;
}

class EditBlocksAction extends AiAction {
  final String pageId;
  final List<EditOp> operations;            // 显式 op
}

sealed class EditOp {}
class InsertOp extends EditOp { String? parentId; String? afterId; BlockJson block; }
class UpdateOp extends EditOp { String id; String expectedHash; BlockPatch patch; }
class ArchiveOp extends EditOp { String id; String expectedHash; }
class MoveOp extends EditOp { String id; String toParentId; String? afterId; }

class SuggestEditAction extends AiAction {
  final String pageId;
  final List<SuggestionDraft> suggestions;  // 转 SuggestionBlock
}

class WriteMarkdownAction extends AiAction {
  final String pageId;
  final String afterBlockId;                // 必填
  final String markdown;
}
```

### 3.4 AiResponse（两阶段协议）

```json
// 阶段一：意图摘要（非 ask 模式必返）
{
  "intent_summary": "在《前端面试题纲》末尾新增「浏览器渲染管线」章节",
  "affected": {
    "pages": [{"id": "...", "title": "..."}],
    "blocks_create": 7,
    "blocks_modify": 0,
    "blocks_archive": 0,
    "new_pages": 0
  },
  "needs_clarification": false,
  "clarification_question": null
}

// 阶段二（用户 Enter 后）：tool_call 序列
// LLM 用拍平的 5 个 tool 之一
```

### 3.5 SuggestionBlock 规范

```json
{
  "type": "suggestion",
  "data": {
    "kind": "replace" | "insert_after" | "archive",
    "target_block_id": "...",
    "target_expected_hash": "...",
    "proposed_block": { /* 完整 Block JSON */ },
    "diff": [ /* 预计算 word-level diff */ ],
    "rationale": "AI 给出的简短理由",
    "plan_id": "ai:plan_xxx",
    "created_at": "2026-05-16T21:03:00+08:00",
    "status": "pending" | "accepted" | "rejected"
  }
}
```

UI 渲染：原块下方浮层（绿增红删），三按钮：✓ 接受 / ✗ 拒绝 / ⋯ 查看理由。接受时系统把它转化为真正的 `UpdateBlock`/`InsertBlock`/`ArchiveBlock` 进 history。

### 3.6 WorkspaceContextBuilder（Token 预算）

```dart
const kMaxOverviewPages = 50;
const kMaxOverviewTokens = 2000;
const kMaxCurrentPageBlocks = 30;
const kMaxTotalContextTokens = 16000;

class AiContext {
  final WorkspaceOverview overview;         // 召回 ≤50 个 page 标题+protection
  final PageContext currentPage;            // 选区周边 30 块
  final List<PageOutline> mentionedPages;   // 用户 @ 的 page 强制包含
  final List<AvailableTool> tools;          // 当前模式可用 tool
  final List<RecentError> recentErrors;     // §3.9 失败学习
  final WorkspaceAiPolicy policy;           // 让 LLM 知道边界
}
```

召回评分：`recency × 0.4 + titleSimilarity × 0.4 + protectionWeight × 0.2`（draft 权重高）。超 token 时丢弃顺序：周边块 < overview < 当前选区。

### 3.7 五层防御（边界清晰版）

| 层          | 职责                                                     | 工具                         | 失败动作                                   |
| ----------- | -------------------------------------------------------- | ---------------------------- | ------------------------------------------ |
| L1 LLM API  | JSON 合法 + enum 合法                                    | tool_use / structured output | 重试 ≤1 次                                |
| L2 Schema   | 字段类型/长度/深度                                       | `AiSchemaValidator`        | 拒绝整 plan                                |
| L3 Plan     | id 存在性 / expected_hash / scope / policy / loop / 循环 | `AiPlanValidator`          | 拒绝整 plan，注入下轮 prompt               |
| L4 Risk     | 风险分级 + 用户确认门                                    | `RiskEvaluator`            | low 自动 / medium SnackBar / high 强制确认 |
| L5 Executor | 事务执行 + Undo unit + Ledger                            | `PlanExecutor`             | 全部回滚                                   |

### 3.8 Risk 评估数值边界

```dart
RiskLevel evaluate(DispatchPlan plan) {
  // 任一即 high
  if (plan.touchedPageProtections.contains(curated)) return high;
  if (plan.affectedPageIds.length >= 2) return high;
  if (plan.workspaceMutations.any((m) => m is CreatePageMutation || m is DeletePageMutation)) return high;
  if (plan.archiveOpsCount >= 5) return high;
  if (plan.totalOpsCount >= 30) return high;
  
  if (plan.archiveOpsCount >= 1 || plan.totalOpsCount >= 10) return medium;
  return low;
}
```

### 3.9 自一致性 + 失败学习

* **high-risk plan** ：自动双采样（temp=0.1 + 0.3），affected scope 偏差 > 20% → 让用户细化指令
* **OpValidator/Schema 拒绝** ：错误原因注入下一轮 system prompt（仅当前会话）
* **`requireReadBeforeWrite`** ：plan 中 update/archive 的 block id 必须在同一会话内被 read 过

### 3.10 LLM 工具集（拍平，5 个）

每个 tool 独立、扁平、`additionalProperties: false`、`required` 完整，深度 ≤ 5：

```
ai_create_page(title, blocks, after_page_id?)
ai_create_database(target_page_id, after_anchor, title, columns, rows)
ai_edit_blocks(page_id, operations[])
ai_suggest_edit(page_id, suggestions[])
ai_write_markdown(page_id, after_block_id, markdown)
```

只读 tool：`read_block`、`read_subtree`、`search_blocks`、`ask_clarification`。

 **每个 tool description 必含否定指令** ：

> "严格规则：(1) 一次最多 10 个 op，超过请拆分；(2) update 必须带 read 时获取的 expected_hash；(3) 不要删除你没刚创建的块，使用 archive；(4) 指令模糊时调用 ask_clarification，不要猜；(5) curated/locked 页面禁止此 tool。"

---

## Part IV · 调度执行层

### 4.1 ActionDispatcher（纯函数，零副作用）

```dart
class ActionDispatcher {
  final WorkspaceManager workspace;
  final OpValidator validator;
  
  /// 唯一公开方法：只生成 plan，不改任何状态
  DispatchPlan plan(List<AiAction> actions, AiScopeFence fence);
}

class DispatchPlan {
  final String planId;
  final String reply;
  final List<WorkspaceMutation> workspaceMutations;   // 先于 ops
  final Map<String, List<BlockOp>> opsByPageId;
  final RiskLevel risk;
  final ScopeImpact impact;                            // 给 UI 渲染用
  final List<ValidationError> errors;
  bool get canExecute => errors.isEmpty;
}

sealed class WorkspaceMutation { String get id; }
class CreatePageMutation extends WorkspaceMutation { /* with full revert info */ }
class ArchivePageMutation extends WorkspaceMutation { final PageSnapshot backup; }
class RenamePageMutation extends WorkspaceMutation { final String oldTitle; }
class SetProtectionMutation extends WorkspaceMutation { final PageProtection old; }
```

 **禁止** ：dispatcher 内部调用 `tree.insert` / `workspace.createPage` / `history.apply`。违反则 lint 报错。

### 4.2 PlanExecutor（事务）

```dart
class PlanExecutor {
  Future<ExecutionResult> execute(DispatchPlan plan) async {
    // 1. 快照所有受影响 page
    final snapshots = <String, String>{};
    for (final pageId in plan.affectedPageIds) {
      snapshots[pageId] = await workspace.snapshots.snapshot(pageId, label: 'pre-${plan.planId}');
    }
  
    final undoStack = <_Undoable>[];
    try {
      // 2. 工作区 mutations
      for (final m in plan.workspaceMutations) {
        undoStack.add(workspace.apply(m));
      }
      // 3. 每页一次 applyBatch（绕过 300ms 合并，作为 1 个 undo unit）
      for (final entry in plan.opsByPageId.entries) {
        final page = workspace.pages[entry.key]!;
        page.controller.history.applyBatch(
          entry.value,
          label: 'ai:${plan.planId}',
          bypassMergeWindow: true,
        );
        undoStack.add(_HistoryUndo(page, entry.value.length));
      }
      // 4. 注册到 UndoCoordinator
      workspace.undo.register(_WorkspaceUndoUnit(plan.planId, undoStack));
      // 5. 写 Ledger
      await workspace.ledger.record(
        planId: plan.planId,
        plan: plan,
        beforeSnapshotIds: snapshots,
        response: /* */,
      );
      return ExecutionResult.success(plan.planId);
    } catch (e) {
      // 倒序回滚
      for (final u in undoStack.reversed) u.undo();
      // 快照保留，用户可手动恢复
      return ExecutionResult.failure(e, snapshots);
    }
  }
}
```

### 4.3 UndoCoordinator

```dart
class UndoCoordinator {
  // 全局栈：page 级 undo 单元 + workspace 级 undo 单元
  // Ctrl+Z 作用于"最近一个"，不论级别
  // 显式区分用户输入（page 级，受 300ms 合并）vs AI plan（workspace 级，不合并）
}
```

---

## Part V · UI 层

### 5.1 唤起 AI

| 场景              | 触发                              |
| ----------------- | --------------------------------- |
| 全局              | `Cmd/Ctrl + K`                  |
| 空 paragraph 行首 | 双击空格 OR `/ai`               |
| 选区上            | 选区右上角浮动 AI 图标            |
| 侧边栏顶部        | "+ AI 创建页面"按钮 → draft 模式 |

### 5.2 AI 输入条

```
┌──────────────────────────────────────────────────────────────┐
│ [Ask ▼]  输入你想做什么...                            [↵ 发送] │
└──────────────────────────────────────────────────────────────┘
   ↑ 模式徽章：ask / append / draft / suggest / edit
   ↑ 当前 page = curated 时，edit 灰显并提示 "页面已完善，仅可建议"
```

### 5.3 意图确认条（阶段一）

```
┌──────────────────────────────────────────────────────────────┐
│ 🤔 计划：在《前端面试题纲》末尾新增「浏览器渲染管线」章节       │
│    📄 1 个页面  ➕ 7 块  ✏️ 0 块  🗄 0 块                       │
│                                          [Esc 取消] [↵ 继续] │
└──────────────────────────────────────────────────────────────┘
```

`needs_clarification=true` 时改为反问输入框。

### 5.4 Plan 预览（阶段二，high-risk 必看）

```
┌──────────────────────────────────────────────────────────────┐
│ 即将应用以下变更（plan_id: xxx）                              │
│                                                              │
│ ▼ 📄 前端面试题纲 (draft)                                     │
│    ➕ 新增 ## 浏览器渲染管线                  [跳转预览]       │
│    ➕ 新增 段落: "浏览器渲染管线分为..."                       │
│    ➕ ...（5 项）                                             │
│                                                              │
│ ▼ 📄 知识库 (curated)  ⚠️ 受保护                              │
│    💡 建议在末尾增加 mention            [接受][拒绝][查看 diff]│
│                                                              │
│ 风险等级: 🟡 medium   60s 后自动重新校验                      │
│                                       [Esc 全部取消] [↵ 应用] │
└──────────────────────────────────────────────────────────────┘
```

每个 update op 必须能展开看 word-level diff。

### 5.5 AI Plan 历史面板

侧边栏底部固定入口"AI 历史"：

* 列出近 20 次 plan
* 每条：时间 / 模式 / 摘要 / 影响页面 / 状态
* 操作：[查看 diff] [一键回滚] [永久删除记录]

### 5.6 错误反馈

* L1/L2 失败：SnackBar "AI 响应格式错误，已自动重试" / "AI 响应无法理解"
* L3 失败：弹窗列出原因 + 注入下轮 prompt
* L5 部分失败：完整回滚 + 弹窗 "已恢复到操作前状态，快照 id: xxx"

---

## Part VI · 工作区策略 & 监控

### 6.1 WorkspaceAiPolicy（用户可配）

```dart
class WorkspaceAiPolicy {
  bool allowEditExistingByDefault = false;
  bool allowDeleteExistingByDefault = false;       // 始终 false（archive）
  int maxOpsPerPlan = 50;
  int maxAffectedPagesPerPlan = 3;
  int maxNewPagesPerPlan = 2;
  Duration confirmationTimeout = Duration(seconds: 60);
  Set<String> alwaysProtectedPageIds = {};         // 钉住保护
  Set<String> protectedTags = {"meeting", "面试"}; // 带标签自动 curated
  bool requireDoubleSampleOnHighRisk = true;
  bool requireReadBeforeWrite = true;
  int snapshotRetentionDays = 30;
  int snapshotRetentionCount = 100;
  int ledgerRetentionCount = 20;
}
```

写到 `workspace.json`。

### 6.2 关键指标 + 自动降级

| 指标                              | 阈值    | 自动动作             |
| --------------------------------- | ------- | -------------------- |
| `ai_plan_reject_rate`           | > 30%   | 提示降级到 ask       |
| `ai_hash_mismatch_rate`         | > 5%    | 暂停写入 5 分钟      |
| `ai_user_undo_rate_60s`         | > 15%   | 当前会话强制 suggest |
| `ai_scope_violation_count`      | > 0     | 报警 + 拒绝该 plan   |
| `protected_page_write_attempts` | > 0     | 报警（应永为 0）     |
| `avg_plan_latency`              | > 8s    | 提示 LLM 状态        |
| `snapshot_disk_usage`           | > 500MB | 触发清理             |

### 6.3 迁移策略（接入前必做）

| 步骤 | 动作                                                                              |
| ---- | --------------------------------------------------------------------------------- |
| 1    | 扫描所有 page，按规则自动打标（>2000字或30天未改 → curated；verified → locked） |
| 2    | 为每个 page 拍 `migration-baseline`快照（永不 evict）                           |
| 3    | 首启动向导：用户逐 page 确认/调整 protection                                      |
| 4    | 灰度：仅 draft page 开放 AI 7 天 → 监控指标 → 才开放 curated 的 suggest         |
| 5    | `edit`模式 + 跨页操作仅在指标全绿 14 天后开放                                   |

---

## Part VII · 实施路线

### 7.1 Phase 划分（强依赖顺序）

| Phase        | 时长 | 内容                                                                                                                                              | 验收门槛                                                         |
| ------------ | ---- | ------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| **P0** | 1 周 | 数据模型修正：删 `BlockType.page`、新增 `databaseRow`/`suggestion`/`ArchiveBlock`；blockId 全局唯一；OpValidator 11 条新规则；contentHash | 现有路径无回归，单测覆盖 ≥90%                                   |
| **P1** | 2 周 | `WorkspaceManager`• 持久化 +`PageSnapshotStore`•`UndoCoordinator`（无 UI）                                                                | 命令行可创建/切换/删除/快照恢复；崩溃恢复一致                    |
| **P2** | 2 周 | `AiAction`• 拍平 tools schema +`ActionDispatcher`(纯) +`DispatchPlan`•`PlanExecutor`(事务) +`AiPlanLedger`                            | plan 失败 0 副作用；plan 成功 = 1 undo unit；100 条 fixture 全绿 |
| **P3** | 2 周 | 五层防御串联 + LLM 集成 + 重试 + 双采样 + 失败学习                                                                                                | 200 条故障注入测试，all-or-nothing                               |
| **P4** | 2 周 | UI：侧边栏、AI 输入条、模式徽章、意图确认、Plan 预览(带 diff)、SuggestionBlock 渲染、AI 历史面板                                                  | 5 个 E2E 用户故事                                                |
| **P5** | 1 周 | 工作区迁移脚本 + 灰度上线 + 指标采集                                                                                                              | 全部 7 条指标接入；迁移可重复执行                                |
| **P6** | 持续 | 跨页 `syncedBlock`• mention +`edit`模式开放 + 模板系统                                                                                       | —                                                               |

### 7.2 客观验收门槛（必须全过才上线）

1. **零双重执行** ：所有 Dispatcher 函数纯函数，静态分析通过
2. **零静默插入** ：`UpdateOp` 命中不存在 id 必报错（fuzz 测试 10000 次）
3. **all-or-nothing** ：100 条故障注入，工作区字节级回到 plan 前
4. **撤销原子性** ：1 次 AI plan = 1 次 Ctrl+Z 完全回退
5. **Schema 严格** ：tools 同时通过 Claude `tools` 与 OpenAI strict `response_format`
6. **Token 上限** ：1000 page 工作区下 context ≤ 16K
7. **持久化一致** ：50 次随机操作 + `kill -9`，重启后无悬挂引用
8. **存量保护** ：100 次 fuzz prompt 攻击 curated/locked page，写入尝试 = 0
9. **快照可还原** ：每个快照都能恢复到字节级原样
10. **延迟** ：plan 校验 P95 < 500ms，执行 P95 < 200ms

---

## 附录 A · 收敛漏斗总图

```
用户输入
  │
  ▼ [L1] 模式选择 / 模糊指令反问 / intent_summary 二次确认
  │
  ▼ [L2] AiScopeFence 构造（仅 @ 提及的 page/block）
  │     curated/locked → 仅 suggest / 仅只读
  │
  ▼ [L3] 工具白名单按模式裁剪
  │     delete → archive；suggest 模式 → SuggestionBlock
  │
  ▼ [L7-AI] 强制 read-before-write / 否定指令 / 双采样
  │
  ▼ Schema 验证（深度/长度/枚举）
  │
  ▼ Plan 验证（id / expected_hash / scope / policy / loop）
  │
  ▼ Risk 评估（数值边界）
  │     high → 强制 Plan 预览 + diff + 60s 重校验
  │
  ▼ 用户在结构化预览上确认
  │
  ▼ PageSnapshot 自动拍照（每个受影响 page）
  │
  ▼ PlanExecutor 事务执行
  │     applyBatch (label='ai:planId', bypassMerge=true)
  │     失败 → 倒序回滚 → 快照保留
  │
  ▼ AiPlanLedger 落盘
  │
  ▼ 文档变更
       ↑ 三级回滚兜底：Ctrl+Z / Plan rollback / Snapshot restore
       ↑ ArchiveBlock 软删除：__archive__ 隐藏页 7 天可恢复
```

---

## 附录 B · 关键源码新增/修改清单

```
lib/core/note/
├── blocks/
│   ├── block_type.dart                    [修改] 删 page，加 databaseRow, suggestion
│   ├── block.dart                         [修改] 加 contentHash
│   ├── block_op.dart                      [修改] 加 ArchiveBlock；UpdateBlock 加 expectedHash
│   ├── op_history.dart                    [修改] applyBatch(label, bypassMergeWindow)
│   ├── op_validator.dart                  [修改] 11 条新规则 + OpValidatorConfig
│   ├── ai/
│   │   ├── ai_mode.dart                   [新增] 5 种模式 + tool 白名单
│   │   ├── ai_scope_fence.dart            [新增]
│   │   ├── ai_action.dart                 [新增] 5 种 Action
│   │   ├── ai_response.dart               [新增] 两阶段协议
│   │   ├── ai_schema_validator.dart       [新增] L2
│   │   ├── ai_plan_validator.dart         [新增] L3
│   │   ├── risk_evaluator.dart            [新增] L4
│   │   ├── action_dispatcher.dart         [新增] 纯函数 plan
│   │   ├── plan_executor.dart             [新增] 事务执行
│   │   ├── workspace_context_builder.dart [新增] token 预算
│   │   ├── llm_client.dart                [新增] 重试 + 双采样 + 失败学习
│   │   ├── ai_plan_ledger.dart            [新增]
│   │   └── suggestion_resolver.dart       [新增] SuggestionBlock → 真 Op
│   └── widgets/
│       ├── ai_input_bar.dart              [新增]
│       ├── ai_mode_badge.dart             [新增]
│       ├── intent_confirmation_bar.dart   [新增]
│       ├── plan_preview_panel.dart        [新增] 带 diff
│       ├── suggestion_block_widget.dart   [新增]
│       └── ai_history_panel.dart          [新增]
├── workspace/
│   ├── workspace_manager.dart             [新增]
│   ├── page_model.dart                    [新增]
│   ├── page_protection.dart               [新增]
│   ├── page_snapshot_store.dart           [新增]
│   ├── undo_coordinator.dart              [新增]
│   ├── workspace_ai_policy.dart           [新增]
│   └── persistence.dart                   [新增] write-ahead
└── bridges/
    └── markdown_bridge.dart               [扩展] 带 afterAnchor
```

---

## 一句话总结

> **AI 输出 Block 树（同模型）→ 受限模式 + 围栏（最小权限）→ 五层防御 + 双采样（拦截幻觉）→ SuggestionBlock + Archive（不破坏存量）→ 事务执行 + 三级回滚 + 自动快照（任何时刻可还原）**

这套方案的破坏面上限是  **0** ：即便所有上层防御全部失效，被 AI 触及的内容也只是变成"待用户接受的建议块"或"可恢复的归档块"，原文档字节级无损。可以放心在已有完善工作区上灰度推进 P0~P5。
