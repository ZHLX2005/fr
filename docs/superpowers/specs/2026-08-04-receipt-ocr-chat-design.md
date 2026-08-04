# 小票 OCR 助手（AI 助手第三入口）

- **日期**: 2026-08-04
- **作者**: Claude (brainstorming → spec)
- **状态**: 设计中（待 user 审阅）

---

## 1. 背景与目标

### 背景
`lib/screens/chat/home_page.dart` 当前有两个 AI 助手入口（Agent / Format）。
本任务新增第三个入口：**「小票」**——把后端 LLM OCR 识别出的小票商品条目（资源/数量/单价/备注）渲染成一张交互卡，每行可独立「记入比价」/「拒绝」，
并在卡片底部提供一个 schema 跳链直达 `fr://lab/demo/price-compare`。

### 业务目标
1. 用户上传或选择一张小票图（demo 阶段用「模拟按钮」触发假后端）
2. 后端返回若干 `LineItem` + `recommendedTopic`
3. 用户在卡片里勾选/操作每一行
4. 用户点底部跳链进入比价器，手动把已记入的条目粘进主题

### 非目标（YAGNI）
- ❌ 真实 OCR 接入（先用假后端硬编码数据）
- ❌ ack 后自动预填比价主题（避免跨 widget/Service 边界复杂度，schema 跳转无参数）
- ❌ 跨会话持久化「已记入」状态
- ❌ 「全部记入 / 全部拒绝」快捷按钮
- ❌ 接入图片选择器 / 相机

---

## 2. 架构概览

```
lib/core/ai_chat/                          ← 在此目录堆叠 ai_chat_sports 与 receipt_ocr
├── agent_chat_page.dart
├── ai_chat_settings_page.dart
├── ai_chat_sports/                        ← 新建空目录，预留运动类入口
│   └── .gitkeep
└── receipt_ocr/                           ← 新建
    ├── receipt_ocr_page.dart              ← 聊天页壳（类似 format_compatibility_page 风格）
    ├── receipt_ocr_models.dart            ← LineItem / ReceiptResult / 行状态枚举
    ├── receipt_ocr_api.dart               ← 假后端 + recognize() 封装
    └── receipt_ocr_router.dart            ← 装到 MessagePanelController

lib/services/message_strategy/             ← 全局消息策略（沿用现有架构）
├── data/receipt_ocr_message_data.dart     ← 新增
├── strategies/receipt_ocr_message_strategy.dart ← 新增（_StatefulWidget 内 state）
├── data/data.dart                         ← 加 export
├── strategies/strategies.dart             ← 加 export
└── di/message_strategy_di.dart            ← 加 ReceiptOcrMessageWidgetStrategy()

lib/screens/chat/home_page.dart            ← 追加第三条 AssistantEntry

lib/lab/demos/price_compare/price_topic_picker_sheet.dart  ← 改成无内部依赖的纯 widget
lib/lab/demos/price_compare_demo.dart      ← 跟着调整 import
```

### 复用现有资产
- **`SchemaText`**（`lib/core/schema/schema_text.dart`）：底部跳链用，格式 `[打开比价计算器](fr://lab/demo/price-compare)`
- **`PriceTopicPickerSheet`**（`lib/lab/demos/price_compare/price_topic_picker_sheet.dart`）：每行「记入」按钮弹它选主题
- **`EmphasisButton.borderEmphasis`**（`lib/core/design/emphasis_button.dart`）：所有按钮用边框强调式
- **`Hive box `price_compare_topics`**：由 PickerSheet 内部读（不需要 receipt_ocr 直接操作）
- **`MessagePanelController` + `MessageWidgetFactory` + `GetIt`**：message 走现有通道

---

## 3. 数据模型

### 3.1 `LineItem`（前端写死 / 后端 LLM 返回的最小单元）

```dart
class LineItem {
  final String resource;     // "红富士苹果"
  final double quantity;     // 2
  final double unitPrice;    // 5.5  ← 后端直接给单价，前端不除
  final String note;         // "盒马"
}
```

### 3.2 `ReceiptResult`（整张小票结果）

```dart
class ReceiptResult {
  final String storeName;        // "盒马鲜生"
  final DateTime purchasedAt;
  final List<LineItem> items;
  final String recommendedTopic; // LLM 给的主题推荐，前端可覆盖
}
```

### 3.3 行状态枚举

```dart
enum ReceiptLineStatus { pending, recorded, rejected }
```

### 3.4 `ReceiptOcrMessageData`

```dart
class ReceiptOcrMessageData implements IMessageData {
  final ReceiptResult result;
  @override String get type => 'receipt_ocr';
}
```

---

## 4. UI 详细

### 4.1 卡片结构（`ReceiptOcrContent` 内 `_StatefulWidget`）

```
┌──────────────────────────────────────────────┐
│ [icon] 盒马鲜生 · 2026-08-04                  │  ← 顶部元信息
├──────────────────────────────────────────────┤
│ 红富士苹果 ×2  ¥5.50 (盒马)    [✓记入] [×拒] │  ← pending 行
│   └ 记入后变成：✓ 已记入「日常水果」           │
├──────────────────────────────────────────────┤
│ 进口香蕉 ×1 ¥12.80 (盒马)     [✓记入] [×拒]  │
├──────────────────────────────────────────────┤
│ 泰国椰青 ×3 ¥9.90 (盒马)      [✓记入] [×拒]  │
├──────────────────────────────────────────────┤
│ [已记入 2/5，拒绝 1]                         │
│ 主题推荐：日常水果                            │
│ [打开比价计算器](fr://lab/demo/price-compare)│  ← SchemaText 链接
└──────────────────────────────────────────────┘
```

### 4.2 单行操作

**pending 行**（右上角两个 IconButton，border-emphasis）：
- 「✓ 记入」→ 弹 `PriceTopicPickerSheet`，默认高亮 `recommendedTopic`
  - 选/建主题后 → 该行进入 `recorded`，显示「✓ 已记入「[主题名]」」（**仅本卡片内标记，不跨 widget 持久化**）
- 「× 拒绝」→ 该行进入 `rejected`：灰底 + 删除线 + 隐藏两个按钮

**recorded 行**：仅显示文字「✓ 已记入「xxx」」（绿色 ✓ + primaryContainer 浅底）
**rejected 行**：删除线 + 灰字，无操作按钮

### 4.3 按钮样式

全部用 `EmphasisButton.borderEmphasis`：
- 「✓ 记入」`color: Theme.of(context).colorScheme.primary`
- 「× 拒绝」`color: Theme.of(context).colorScheme.error`

**IconButton 实现**：`OutlinedButton.icon` 迷你版 — 用 `IconButton` 套 `EmphasisButton.borderEmphasis` 的同色边框 + 同色背景，size 缩到 32×32。

> 实现参考：把 IconButton 包在 `Container(decoration: BoxDecoration(color, border))` 里，和 `EmphasisButton` 视觉一致。

### 4.4 底部跳链

```dart
Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: theme.colorScheme.primary.withValues(alpha: 0.06),
    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
  ),
  child: Row(
    children: [
      Expanded(child: _buildStatusSummary()),
      const SizedBox(width: 12),
      Expanded(child: SchemaText('[打开比价计算器](fr://lab/demo/price-compare)')),
    ],
  ),
)
```

---

## 5. 假后端

`receipt_ocr_api.dart`：

```dart
class ReceiptOcrApi {
  /// 假后端：等待 800ms 返回硬编码数据，模拟 LLM 识别
  static Future<ReceiptResult> recognize() async {
    await Future.delayed(const Duration(milliseconds: 800));
    return ReceiptResult(
      storeName: '盒马鲜生',
      purchasedAt: DateTime.now(),
      recommendedTopic: '日常水果',
      items: const [
        LineItem(resource: '红富士苹果', quantity: 2, unitPrice: 5.5, note: '盒马'),
        LineItem(resource: '进口香蕉',   quantity: 1, unitPrice: 12.8, note: '盒马'),
        LineItem(resource: '泰国椰青',   quantity: 3, unitPrice: 9.9, note: '盒马'),
        LineItem(resource: '巨峰葡萄',   quantity: 1, unitPrice: 28.0, note: '盒马'),
        LineItem(resource: '云南蓝莓',   quantity: 2, unitPrice: 19.9, note: '盒马'),
      ],
    );
  }
}
```

---

## 6. 页面壳（`receipt_ocr_page.dart`）

复用 `format_compatibility_page.dart` 的结构：
- AppBar：icon `Icons.receipt_long` + 「小票」+「OCR 识别 → 快速比价」
- 主体：`MessagePanelController` 监听 + 单条 message 渲染
- 底部：单一按钮「模拟一次识别」→ 调假后端 → `factory.createMockData` 拿壳 → `_panel.append(...)`

**没有输入框**，只有一个「识别」按钮触发（demo 阶段够用）。后续接真实 OCR 时再加图片选择。

---

## 7. 修改现有文件

### 7.1 `lib/lab/demos/price_compare/price_topic_picker_sheet.dart`
当前依赖 `price_compare_models.dart`。改成无内部依赖的纯 widget：
- `entries` 改为 `List<{id, title, rowCount, createdAt}>`（与原 `Map` 形状对齐）
- `onDelete` 仍保留，外部自行处理

调用方变化：`price_compare_demo.dart` 原来传 `Map`，现在传一个简单 Map（`{'id': ..., 'title': ..., 'rowCount': ..., 'createdAt': ...}`），`onDelete` 内部用 box。

### 7.2 `lib/screens/chat/home_page.dart`
追加第三条 `AssistantEntry`：
```dart
AssistantEntry(
  icon: Icons.receipt_long,
  title: '小票',
  subtitle: 'OCR 识别 → 快速比价',
  color: (context) => Theme.of(context).colorScheme.tertiary,
  builder: (context) => const ReceiptOcrPage(),
),
```

### 7.3 `lib/services/message_strategy/`
- `data/data.dart` 加 `export 'receipt_ocr_message_data.dart';`
- `strategies/strategies.dart` 加 `export 'receipt_ocr_message_strategy.dart';`
- `di/message_strategy_di.dart` 在 `strategyInstances` 列表里加 `ReceiptOcrMessageWidgetStrategy()`

---

## 8. 错误处理

| 场景 | 处理 |
|---|---|
| 假后端超时（Future.delayed 内部 throw） | SnackBar 错误提示，不污染卡片 |
| 用户拒绝全部 5 项 | 卡片仍正常显示，底部状态「0/5 已记入，5 拒绝」 |
| 用户全部记入 | 同上 |
| 跳链点击无反应 | `frRouter.handle` 内部已有 fallback（`lib/core/schema/fr_router.dart`），无需额外处理 |
| `PriceTopicPickerSheet` 内 delete 后没有剩余主题 | sheet 自身提示「新建」 |

---

## 9. 测试 / 验证

### 9.1 静态检查
- `flutter analyze lib/core/ai_chat/receipt_ocr/ lib/services/message_strategy/ lib/screens/chat/home_page.dart`
- 必须 `No issues found`

### 9.2 手动验证清单
1. **进入路径**：Home → 「小票」→ 进页面，空状态
2. **点识别按钮**：800ms 后出现一张 receipt_ocr 卡，5 行 pending
3. **行操作**：
   - 点 ✓ → 弹 PickerSheet → 选「日常水果」→ 行变成「✓ 已记入「日常水果」」
   - 点 × → 行灰化删除线
   - rejected 行不能再次操作
4. **底部状态**：随操作实时更新「已记入 X/5」
5. **跳链**：点底部 [打开比价计算器] → 进入比价器页面
6. **Hive 持久化**：比价器内新建/删除主题，PickerSheet 正确反映
7. **重启 App**：Home → 「小票」→ 直接看到已识别的卡（**面板是全局单例**，所以保留上次结果）

### 9.3 边界用例
- 一行全 5 项都拒绝：卡片不崩
- 推荐主题 `recommendedTopic` 在 PickerSheet 中不存在（被删除）：sheet 仍正常显示，标题栏显示「（未命名主题）」等价处理

---

## 10. 实施步骤（将由 writing-plans 拆解）

1. **基础层**：建 `lib/core/ai_chat/ai_chat_sports/.gitkeep` + `receipt_ocr/{models,api}` 两个文件，定义 `LineItem / ReceiptResult`
2. **拆 sheet**：把 `PriceTopicPickerSheet` 从 `Map` 改成轻量 record 类型，调整 `price_compare_demo.dart`
3. **message 策略**：写 `receipt_ocr_message_data.dart` + `receipt_ocr_message_strategy.dart`，注册到 data/strategies/di
4. **router**：写 `receipt_ocr_router.dart`（组装 mock → panel）
5. **页面壳**：写 `receipt_ocr_page.dart`
6. **首页入口**：`home_page.dart` 加第三条
7. **分析**：`flutter analyze` 跑通

---

## 11. 风险与权衡

| 风险 | 缓解 |
|---|---|
| PickerSheet 改动影响原 price_compare_demo | 改动是结构性的（类型更明确），行为不变；flutter analyze + 手动验证 5 分钟内可排除 |
| 边框强调式 IconButton 自己包 Container 视觉不够"原生" | 复用 `EmphasisButton.borderEmphasis` 的颜色 token，保持一致 |
| `_StatefulWidget` 内 state 在卡片重建时丢失 | 仅当父 widget 整体重建时才会重建；`MessagePanelController` 是全局单例不会触发父 rebuild，可接受 |

---

## 12. 后续（不在本任务）

- 接真实 OCR 上传图片
- 多张 receipt_ocr 卡共存（本次只演示 1 张）
- ack 后通过 schema query 参数预填到比价主题
- 跨会话持久化「已记入」标记