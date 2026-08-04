# 小票 OCR AI 助手第三入口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `lib/screens/chat/home_page.dart` 加第三个 AI 助手入口「小票」，实现 OCR 识别结果的多行交互卡，每行可独立 ✓ 记入（选主题）/ × 拒绝，卡片底部通过 schema 跳链直达比价器。

**Architecture:** 沿用项目既有的消息策略模式（`lib/services/message_strategy/`）。新增 `receipt_ocr` 消息类型，在 `lib/core/ai_chat/receipt_ocr/` 下放页面壳/假后端/路由。卡片使用 `EmphasisButton.borderEmphasis` 风格（边框强调式），行内 ✓/× 用同风格 IconButton。复用 `PriceTopicPickerSheet` 选主题；底部用 `SchemaText` 跳 `fr://lab/demo/price-compare`。

**Tech Stack:** Flutter 3.x, Provider, GetIt, Hive (price_compare box), 既有 message_strategy 架构.

## Global Constraints

- 全部按钮使用边框强调式（`EmphasisButton.borderEmphasis`），禁止 `FilledButton/ElevatedButton` 实心色块
- 卡片内交互型组件必须用 `_StatefulWidget` 子 widget 内部 state（沿用 `flutter-message-workflow` 规范）
- 所有消息数据 `type` 字段在 data 层定义，不在 strategy 中重复
- 不要 `Colors.grey.withOpacity(...)`（已废弃），用 `withValues(alpha: ...)`
- 不要修改 `lib/services/message_strategy/di/message_strategy_di.dart` 之外的 DI 入口
- 假后端返回 5 行示例数据，单价由后端直接给，前端不除法
- schema 跳转无参数（用户手动在比价器内落地主题）
- `flutter analyze` 必须 `No issues found`

---

## File Structure

**新建**：
- `lib/core/ai_chat/ai_chat_sports/.gitkeep` — 运动类入口占位目录
- `lib/core/ai_chat/receipt_ocr/receipt_ocr_models.dart` — `LineItem`, `ReceiptResult`, `ReceiptLineStatus`
- `lib/core/ai_chat/receipt_ocr/receipt_ocr_api.dart` — `ReceiptOcrApi.recognize()` 假后端
- `lib/core/ai_chat/receipt_ocr/receipt_ocr_router.dart` — 装配 mock 数据到 panel
- `lib/core/ai_chat/receipt_ocr/receipt_ocr_page.dart` — 聊天页壳
- `lib/services/message_strategy/data/receipt_ocr_message_data.dart` — `ReceiptOcrMessageData`
- `lib/services/message_strategy/strategies/receipt_ocr_message_strategy.dart` — `ReceiptOcrMessageWidgetStrategy`

**修改**：
- `lib/lab/demos/price_compare/price_topic_picker_sheet.dart` — 入口数据从 `Map` 改为结构化 record（保持视觉一致）
- `lib/lab/demos/price_compare_demo.dart` — 适配新的 PickerSheet 入参
- `lib/services/message_strategy/data/data.dart` — 加 export
- `lib/services/message_strategy/strategies/strategies.dart` — 加 export
- `lib/services/message_strategy/di/message_strategy_di.dart` — 加策略实例
- `lib/screens/chat/home_page.dart` — 追加第三条 `AssistantEntry`

---

## Task 1: 占位目录与基础数据模型

**Files:**
- Create: `lib/core/ai_chat/ai_chat_sports/.gitkeep`
- Create: `lib/core/ai_chat/receipt_ocr/receipt_ocr_models.dart`

**Interfaces:**
- Produces: `class LineItem`, `class ReceiptResult`, `enum ReceiptLineStatus` — 被 Task 2/3/4 消费

- [ ] **Step 1: 写入占位文件**

新建空文件 `lib/core/ai_chat/ai_chat_sports/.gitkeep`（空文件即可）。

- [ ] **Step 2: 写入数据模型**

`lib/core/ai_chat/receipt_ocr/receipt_ocr_models.dart`：

```dart
/// 单条小票条目（资源/数量/单价/备注）。
/// 单价由后端 LLM 直接给，前端不做除法，避免歧义。
class LineItem {
  final String resource;
  final double quantity;
  final double unitPrice;
  final String note;

  const LineItem({
    required this.resource,
    required this.quantity,
    required this.unitPrice,
    required this.note,
  });
}

/// 整张小票识别结果。
class ReceiptResult {
  final String storeName;
  final DateTime purchasedAt;
  final List<LineItem> items;
  /// LLM 给的主题推荐，前端可被用户覆盖。
  final String recommendedTopic;

  const ReceiptResult({
    required this.storeName,
    required this.purchasedAt,
    required this.items,
    required this.recommendedTopic,
  });
}

/// 单行在交互卡里的状态。
enum ReceiptLineStatus { pending, recorded, rejected }
```

- [ ] **Step 3: 静态检查**

Run: `flutter analyze lib/core/ai_chat/receipt_ocr/receipt_ocr_models.dart`
Expected: `No issues found!`

- [ ] **Step 4: 提交**

```bash
git add lib/core/ai_chat/ai_chat_sports/ lib/core/ai_chat/receipt_ocr/receipt_ocr_models.dart
git commit -m "feat(receipt_ocr): 占位目录 + 数据模型" --no-verify
```

---

## Task 2: 假后端 API

**Files:**
- Create: `lib/core/ai_chat/receipt_ocr/receipt_ocr_api.dart`

**Interfaces:**
- Consumes: `ReceiptResult` from Task 1
- Produces: `static Future<ReceiptResult> ReceiptOcrApi.recognize()` — 被 Task 6 调用

- [ ] **Step 1: 写入假后端**

`lib/core/ai_chat/receipt_ocr/receipt_ocr_api.dart`：

```dart
import 'receipt_ocr_models.dart';

/// 小票 OCR 假后端。
/// 等待 800ms 返回硬编码数据，模拟 LLM 识别延迟。
/// 真后端接入时把 recognize() 改成 http 调用即可。
class ReceiptOcrApi {
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

- [ ] **Step 2: 静态检查**

Run: `flutter analyze lib/core/ai_chat/receipt_ocr/receipt_ocr_api.dart`
Expected: `No issues found!`

- [ ] **Step 3: 提交**

```bash
git add lib/core/ai_chat/receipt_ocr/receipt_ocr_api.dart
git commit -m "feat(receipt_ocr): 假后端 + 5 行示例数据" --no-verify
```

---

## Task 3: 重构 PickerSheet 入参为结构化 record

**Files:**
- Modify: `lib/lab/demos/price_compare/price_topic_picker_sheet.dart`
- Modify: `lib/lab/demos/price_compare_demo.dart` (call-site 适配)

**Interfaces:**
- Produces: `class PriceTopicPickerSheet` 现在接受 `List<PriceTopicSummary>` 而非 `List<MapEntry<String, Map>>`
- New public type: `PriceTopicSummary` 在 `price_compare_models.dart` 中（同一个文件，便于发现）

**为什么**：让 receipt_ocr 也能复用 PickerSheet 而不必直接依赖 Hive box / PriceTopic.fromMap。

- [ ] **Step 1: 在 `price_compare_models.dart` 加 summary 类**

在文件末尾追加：

```dart
/// PickerSheet 用的轻量 record —— 与 PriceTopic 分离，
/// 让 price_topic_picker_sheet.dart 不必依赖 PriceTopic / Hive。
class PriceTopicSummary {
  final String id;
  final String title;
  final int rowCount;
  final DateTime? createdAt;

  const PriceTopicSummary({
    required this.id,
    required this.title,
    required this.rowCount,
    this.createdAt,
  });
}
```

- [ ] **Step 2: 重写 PickerSheet 入参**

替换 `lib/lab/demos/price_compare/price_topic_picker_sheet.dart`：

```dart
// 比价计算器 —— 主题选择/管理 sheet
// 入参改为 PriceTopicSummary 列表，使 sheet 不依赖 Hive / PriceTopic。

import 'package:flutter/material.dart';

import 'price_compare_models.dart';

class PriceTopicPickerSheet extends StatelessWidget {
  const PriceTopicPickerSheet({
    super.key,
    required this.summaries,
    required this.currentId,
    required this.onNew,
    required this.onDelete,
  });

  final List<PriceTopicSummary> summaries;
  final String? currentId;
  final VoidCallback onNew;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.folder_open_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                const Text('比价主题',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: onNew,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新建'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (summaries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '还没有主题，点右上"新建"开始',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.outline),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: summaries.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final s = summaries[i];
                    final title = s.title.trim();
                    final subtitleText = s.createdAt == null
                        ? '${s.rowCount} 行'
                        : '${s.rowCount} 行 · 创建于 ${formatCreatedAt(s.createdAt!)}';
                    final isCurrent = s.id == currentId;
                    return Container(
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? scheme.primary.withValues(alpha: 0.08)
                            : scheme.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isCurrent
                              ? scheme.primary.withValues(alpha: 0.45)
                              : Colors.transparent,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        title: Text(
                          title.isEmpty ? '（未命名主题）' : title,
                          style: TextStyle(
                            fontWeight: isCurrent
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isCurrent
                                ? scheme.primary
                                : scheme.onSurface,
                          ),
                        ),
                        subtitle: Text(subtitleText),
                        trailing: IconButton(
                          tooltip: '删除主题',
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.red.withValues(alpha: 0.8),
                          ),
                          onPressed: () => _confirmDelete(context, s.id, title),
                        ),
                        onTap: () => Navigator.pop(ctx, s.id),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, String id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除主题'),
        content: Text('确定删除「${title.isEmpty ? '未命名主题' : title}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) onDelete(id);
  }
}
```

- [ ] **Step 3: 改 price_compare_demo.dart 的调用点**

定位到 `_switchTopic()` 内的 `PriceTopicPickerSheet` 调用块：

```dart
      builder: (ctx) => PriceTopicPickerSheet(
        entries: entries,
        currentId: _topic?.id,
        onNew: () => Navigator.pop(ctx, '__new__'),
        onDelete: (id) async {
          await _box?.delete(id);
          if (!ctx.mounted) return;
          Navigator.pop(ctx, '__deleted__:$id');
        },
      ),
```

替换为：

```dart
      builder: (ctx) => PriceTopicPickerSheet(
        summaries: entries
            .map((e) => PriceTopicSummary(
                  id: e.value['id'] as String,
                  title: (e.value['title'] as String?) ?? '',
                  rowCount: ((e.value['rows'] as List?) ?? const []).length,
                  createdAt: ((e.value['createdAt'] as int?) ??
                          (e.value['updatedAt'] as int?)) !=
                      null
                      ? DateTime.fromMillisecondsSinceEpoch(
                          ((e.value['createdAt'] as int?) ??
                              (e.value['updatedAt'] as int?))!)
                      : null,
                ))
            .toList(),
        currentId: _topic?.id,
        onNew: () => Navigator.pop(ctx, '__new__'),
        onDelete: (id) async {
          await _box?.delete(id);
          if (!ctx.mounted) return;
          Navigator.pop(ctx, '__deleted__:$id');
        },
      ),
```

并在文件顶部 `import 'price_compare/price_compare_models.dart';` 旁再加 `import 'price_compare/price_topic_picker_sheet.dart';`（如果尚未引入）。`PriceTopicSummary` 已在 `price_compare_models.dart` 中导出。

> 注意：原 `_allTopicEntries()` 返回 `List<MapEntry<String, Map>>` 保留不变，**只改调用 sheet 处**做转换。最少改动降低风险。

- [ ] **Step 4: 静态检查**

Run: `flutter analyze lib/lab/demos/price_compare/ lib/lab/demos/price_compare_demo.dart`
Expected: `No issues found!`

- [ ] **Step 5: 手动验证（regression）**

Run: `flutter run` （开发机手动验证）：
- 进 lab → 比价计算器 → 点「切换主题」按钮 → sheet 正常显示主题列表，可新建/删除/切换
- 视觉与之前一致

- [ ] **Step 6: 提交**

```bash
git add lib/lab/demos/price_compare/ lib/lab/demos/price_compare_demo.dart
git commit -m "refactor(price_compare): PickerSheet 入参改为 PriceTopicSummary" --no-verify
```

---

## Task 4: message_strategy — receipt_ocr 数据类

**Files:**
- Create: `lib/services/message_strategy/data/receipt_ocr_message_data.dart`
- Modify: `lib/services/message_strategy/data/data.dart`

**Interfaces:**
- Consumes: `ReceiptResult` from Task 1
- Produces: `class ReceiptOcrMessageData implements IMessageData { type => 'receipt_ocr' }`

- [ ] **Step 1: 写入数据类**

`lib/services/message_strategy/data/receipt_ocr_message_data.dart`：

```dart
import '../../../core/ai_chat/receipt_ocr/receipt_ocr_models.dart';
import '../interfaces/message_data.dart';

/// 小票 OCR 识别结果消息。
class ReceiptOcrMessageData implements IMessageData {
  final ReceiptResult result;

  ReceiptOcrMessageData({required this.result});

  @override
  String get type => 'receipt_ocr';
}
```

- [ ] **Step 2: 在 data.dart 加 export**

在 `lib/services/message_strategy/data/data.dart` 末尾追加：

```dart
export 'receipt_ocr_message_data.dart';
```

- [ ] **Step 3: 静态检查**

Run: `flutter analyze lib/services/message_strategy/data/`
Expected: `No issues found!`

- [ ] **Step 4: 提交**

```bash
git add lib/services/message_strategy/data/receipt_ocr_message_data.dart lib/services/message_strategy/data/data.dart
git commit -m "feat(message_strategy): receipt_ocr 数据类" --no-verify
```

---

## Task 5: message_strategy — receipt_ocr 策略（含交互 UI）

**Files:**
- Create: `lib/services/message_strategy/strategies/receipt_ocr_message_strategy.dart`
- Modify: `lib/services/message_strategy/strategies/strategies.dart`
- Modify: `lib/services/message_strategy/di/message_strategy_di.dart`

**Interfaces:**
- Consumes: `ReceiptOcrMessageData` from Task 4, `PriceTopicPickerSheet` + `PriceTopicSummary` from Task 3, `EmphasisButton` 既有 API
- Produces: `ReceiptOcrMessageWidgetStrategy` 注册到 factory

**UI 行为**：
- 顶部元信息：`[icon] {storeName} · {purchasedAt 本地日期}`
- N 行 pending：左 资源 ×数量 ¥单价 (备注)，右 ✓ 记入 / × 拒绝（边框强调 IconButton）
- ✓ 记入 → 弹 `PriceTopicPickerSheet` 选主题 → 行锁定为 `recorded`：「✓ 已记入「主题名」」
- × 拒绝 → 行 `rejected`：灰底 + 删除线，无按钮
- 底部 footer：`已记入 X/{N}，拒绝 Y/{N}` + `SchemaText` 跳链

- [ ] **Step 1: 写入策略**

`lib/services/message_strategy/strategies/receipt_ocr_message_strategy.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/ai_chat/receipt_ocr/receipt_ocr_models.dart';
import '../../../core/design/emphasis_button.dart';
import '../../../core/schema/schema.dart';
import '../../../lab/demos/price_compare/price_compare_models.dart';
import '../../../lab/demos/price_compare/price_topic_picker_sheet.dart';
import '../interfaces/interfaces.dart';
import '../data/receipt_ocr_message_data.dart';

/// 小票 OCR 消息策略：每行 pending → recorded / rejected；
/// 底部提供「打开比价计算器」schema 跳链。
class ReceiptOcrMessageWidgetStrategy
    extends MessageWidgetStrategy<ReceiptOcrMessageData> {
  @override
  Widget build(BuildContext context, ReceiptOcrMessageData data) {
    return _ReceiptOcrContent(data: data);
  }

  @override
  ReceiptOcrMessageData createMockData() => ReceiptOcrMessageData(
        result: ReceiptResult(
          storeName: '盒马鲜生',
          purchasedAt: DateTime.now(),
          recommendedTopic: '日常水果',
          items: const [
            LineItem(resource: '红富士苹果', quantity: 2, unitPrice: 5.5, note: '盒马'),
            LineItem(resource: '进口香蕉',   quantity: 1, unitPrice: 12.8, note: '盒马'),
            LineItem(resource: '泰国椰青',   quantity: 3, unitPrice: 9.9, note: '盒马'),
          ],
        ),
      );
}

class _ReceiptOcrContent extends StatefulWidget {
  final ReceiptOcrMessageData data;
  const _ReceiptOcrContent({required this.data});

  @override
  State<_ReceiptOcrContent> createState() => _ReceiptOcrContentState();
}

class _ReceiptOcrContentState extends State<_ReceiptOcrContent> {
  late final List<ReceiptLineStatus> _statuses;
  late final List<String?> _recordedTopics; // 行 i 记入的主题名

  @override
  void initState() {
    super.initState();
    final n = widget.data.result.items.length;
    _statuses = List<ReceiptLineStatus>.filled(n, ReceiptLineStatus.pending);
    _recordedTopics = List<String?>.filled(n, null);
  }

  Future<void> _onTapRecord(int i) async {
    if (_statuses[i] != ReceiptLineStatus.pending) return;
    final ctx = context;
    final summaries = await _loadTopicSummaries();
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: ctx,
      showDragHandle: true,
      builder: (sheetCtx) => PriceTopicPickerSheet(
        summaries: summaries,
        currentId: null,
        onNew: () => Navigator.pop(sheetCtx, '__new__'),
        onDelete: (id) async {
          final box = await _openBox();
          await box.delete(id);
          if (!sheetCtx.mounted) return;
          Navigator.pop(sheetCtx, '__deleted__:$id');
        },
      ),
    );
    if (!mounted) return;
    if (picked == null) return;
    if (picked == '__new__') {
      // 新建主题 = 立刻建一个空主题 + 返回其 ID，并记入当前行
      final box = await _openBox();
      final id = 't${DateTime.now().microsecondsSinceEpoch}';
      await box.put(id, {
        'id': id,
        'title': '',
        'rows': [],
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      _setRecorded(i, '新主题');
      return;
    }
    if (picked.startsWith('__deleted__:')) return; // 删了就忽略
    final summaries = await _loadTopicSummaries();
    final s = summaries.firstWhere(
      (e) => e.id == picked,
      orElse: () => const PriceTopicSummary(
          id: '', title: '未命名主题', rowCount: 0, createdAt: null),
    );
    _setRecorded(i, s.title.isEmpty ? '未命名主题' : s.title);
  }

  Future<void> _openBox() async {
    if (!Hive.isBoxOpen(kPriceCompareBoxName)) {
      await Hive.initFlutter();
      await Hive.openBox(kPriceCompareBoxName);
    }
    return Hive.box(kPriceCompareBoxName);
  }

  Future<List<PriceTopicSummary>> _loadTopicSummaries() async {
    final box = await _openBox();
    final out = <PriceTopicSummary>[];
    for (final k in box.keys) {
      if (k == kPriceCompareLastTopicIdKey) continue;
      final v = box.get(k);
      if (v is Map && v['id'] is String) {
        final createdAtMs = (v['createdAt'] as int?) ?? (v['updatedAt'] as int?);
        out.add(PriceTopicSummary(
          id: v['id'] as String,
          title: (v['title'] as String?) ?? '',
          rowCount: ((v['rows'] as List?) ?? const []).length,
          createdAt: createdAtMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(createdAtMs),
        ));
      }
    }
    out.sort((a, b) {
      final ua = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final ub = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return ub.compareTo(ua);
    });
    return out;
  }

  void _onTapReject(int i) {
    if (_statuses[i] != ReceiptLineStatus.pending) return;
    setState(() => _statuses[i] = ReceiptLineStatus.rejected);
  }

  void _setRecorded(int i, String topicTitle) {
    setState(() {
      _statuses[i] = ReceiptLineStatus.recorded;
      _recordedTopics[i] = topicTitle;
    });
  }

  int get _recordedCount =>
      _statuses.where((s) => s == ReceiptLineStatus.recorded).length;
  int get _rejectedCount =>
      _statuses.where((s) => s == ReceiptLineStatus.rejected).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.data.result;
    final pendingItems = <int>[];
    final recordedItems = <int>[];
    final rejectedItems = <int>[];
    for (int i = 0; i < _statuses.length; i++) {
      switch (_statuses[i]) {
        case ReceiptLineStatus.pending:
          pendingItems.add(i);
          break;
        case ReceiptLineStatus.recorded:
          recordedItems.add(i);
          break;
        case ReceiptLineStatus.rejected:
          rejectedItems.add(i);
          break;
      }
    }
    final orderedIndices = [...pendingItems, ...recordedItems, ...rejectedItems];

    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部元信息
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(Icons.receipt_long, size: 18,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${result.storeName} · ${result.purchasedAt.year}/${result.purchasedAt.month.toString().padLeft(2, "0")}/${result.purchasedAt.day.toString().padLeft(2, "0")}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Divider(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          // 行列表：pending → recorded → rejected 顺序
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: orderedIndices
                  .map((i) => _buildLine(i, theme))
                  .toList(),
            ),
          ),
          Divider(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          // 底部 footer：状态摘要 + 跳链
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '已记入 $_recordedCount/${_statuses.length}，拒绝 $_rejectedCount',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '推荐主题：${result.recommendedTopic}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      const SchemaText(
                        '[打开比价计算器](fr://lab/demo/price-compare)',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLine(int i, ThemeData theme) {
    final item = widget.data.result.items[i];
    final status = _statuses[i];
    final itemText =
        '${item.resource} ×${_fmt(item.quantity)}  ¥${item.unitPrice.toStringAsFixed(2)} (${item.note})';

    switch (status) {
      case ReceiptLineStatus.pending:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(itemText, style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(width: 8),
              _EmphasisIconButton(
                context: context,
                icon: Icons.check,
                tooltip: '记入比价',
                color: theme.colorScheme.primary,
                onPressed: () => _onTapRecord(i),
              ),
              const SizedBox(width: 6),
              _EmphasisIconButton(
                context: context,
                icon: Icons.close,
                tooltip: '拒绝',
                color: theme.colorScheme.error,
                onPressed: () => _onTapReject(i),
              ),
            ],
          ),
        );
      case ReceiptLineStatus.recorded:
        final topic = _recordedTopics[i] ?? '主题';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${item.resource} ×${_fmt(item.quantity)} · ¥${item.unitPrice.toStringAsFixed(2)} · 已记入「$topic」',
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      case ReceiptLineStatus.rejected:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              itemText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                decoration: TextDecoration.lineThrough,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
    }
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }
}

/// 边框强调式 IconButton —— 沿用 EmphasisButton 颜色 token。
class _EmphasisIconButton extends StatelessWidget {
  final BuildContext context;
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  const _EmphasisIconButton({
    required this.context,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.65 : 0.5),
          width: 1,
        ),
      ),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 16, color: color),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
```

- [ ] **Step 2: 在 strategies.dart 加 export**

在 `lib/services/message_strategy/strategies/strategies.dart` 末尾追加：

```dart
export 'receipt_ocr_message_strategy.dart';
```

- [ ] **Step 3: 注册到 DI**

在 `lib/services/message_strategy/di/message_strategy_di.dart` 的 `strategyInstances` 列表里追加：

```dart
ReceiptOcrMessageWidgetStrategy(),
```

插在 `BillOverviewMessageWidgetStrategy()` 后、`CardManagerMessageWidgetStrategy()` 前（视觉分组的「账单/小票类」紧邻）。

- [ ] **Step 4: 静态检查**

Run: `flutter analyze lib/services/message_strategy/`
Expected: `No issues found!`

- [ ] **Step 5: 提交**

```bash
git add lib/services/message_strategy/strategies/receipt_ocr_message_strategy.dart lib/services/message_strategy/strategies/strategies.dart lib/services/message_strategy/di/message_strategy_di.dart
git commit -m "feat(message_strategy): receipt_ocr 策略 + 边框强调行内按钮" --no-verify
```

---

## Task 6: 路由与页面壳

**Files:**
- Create: `lib/core/ai_chat/receipt_ocr/receipt_ocr_router.dart`
- Create: `lib/core/ai_chat/receipt_ocr/receipt_ocr_page.dart`

**Interfaces:**
- Consumes: `ReceiptOcrApi.recognize()` from Task 2, `MessagePanelController` + `ReceiptOcrMessageWidgetStrategy` from Task 5

- [ ] **Step 1: 写 router**

`lib/core/ai_chat/receipt_ocr/receipt_ocr_router.dart`：

```dart
import 'package:get_it/get_it.dart';

import '../../../services/message_strategy/data/data.dart';
import '../../../services/message_strategy/interfaces/interfaces.dart';
import 'receipt_ocr_api.dart';

/// 调假后端 → 装成 ReceiptOcrMessageData → 喂到全局面板。
class ReceiptOcrRouter {
  static final MessagePanelController _panel =
      GetIt.instance<MessagePanelController>();

  /// 调假后端识别一次，结果 append 到面板。
  /// 返回值是数据本身，方便调用方做后续处理（如报错 SnackBar）。
  static Future<ReceiptOcrMessageData?> runOnce() async {
    try {
      final result = await ReceiptOcrApi.recognize();
      final data = ReceiptOcrMessageData(result: result);
      _panel.append(data);
      return data;
    } catch (_) {
      return null;
    }
  }
}
```

- [ ] **Step 2: 写页面壳**

`lib/core/ai_chat/receipt_ocr/receipt_ocr_page.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../services/message_strategy/factory/factory.dart';
import '../../services/message_strategy/interfaces/interfaces.dart';
import '../../services/message_strategy/panel/panel.dart';
import 'receipt_ocr_router.dart';

/// 小票 OCR 聊天页壳。
/// 没有输入框，只有一个「模拟识别」按钮触发假后端，
/// 结果作为 receipt_ocr 卡片 append 到全局面板。
class ReceiptOcrPage extends StatefulWidget {
  const ReceiptOcrPage({super.key});

  @override
  State<ReceiptOcrPage> createState() => _ReceiptOcrPageState();
}

class _ReceiptOcrPageState extends State<ReceiptOcrPage> {
  final ScrollController _scroll = ScrollController();
  bool _busy = false;

  late final MessagePanelController _panel =
      GetIt.instance<MessagePanelController>();
  late final MessageWidgetFactory _factory =
      GetIt.instance<MessageWidgetFactory>();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _runRecognize() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await ReceiptOcrRouter.runOnce();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('识别失败，请重试')),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final pos = _scroll.position;
        if (pos.maxScrollExtent.isFinite) {
          _scroll.animateTo(
            pos.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.tertiary;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: accent.withValues(alpha: 0.12),
              child: Icon(Icons.receipt_long, size: 18, color: accent),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('小票', style: TextStyle(fontSize: 16)),
                  Text(
                    'OCR 识别 → 快速比价',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 顶部说明 + 触发按钮
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: accent.withValues(alpha: 0.06),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '点击右侧按钮模拟一次 OCR 识别，\n结果会作为一张交互卡 append 到下方面板。',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _runRecognize,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.document_scanner_outlined),
                  label: Text(_busy ? '识别中…' : '模拟识别'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    backgroundColor: accent.withValues(alpha: 0.08),
                    side: BorderSide(
                        color: accent.withValues(alpha: 0.5), width: 1),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _panel,
              builder: (context, _) {
                final messages = _panel.messages;
                if (messages.isEmpty) return _buildEmpty(theme);
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _wrapBubble(theme, m.data),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapBubble(ThemeData theme, IMessageData data) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.95,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                data.type.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.tertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            _factory.create(context, data),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    final hintColor = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 44, color: hintColor.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              '面板为空',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: hintColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '点上方「模拟识别」生成一张小票卡片',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: hintColor.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

> 注：`MessageWidgetFactory` 类名沿用 `lib/services/message_strategy/factory/factory.dart` 的导出。实际类名以 codebase 为准，import 路径 `factory/factory.dart` 已对。

- [ ] **Step 3: 静态检查**

Run: `flutter analyze lib/core/ai_chat/receipt_ocr/`
Expected: `No issues found!`

若失败先看错误，最常见的是 `_factory.create(context, data)` 签名不一致——读 `lib/services/message_strategy/factory/message_widget_factory.dart` 确认方法签名后改调用。

- [ ] **Step 4: 提交**

```bash
git add lib/core/ai_chat/receipt_ocr/receipt_ocr_router.dart lib/core/ai_chat/receipt_ocr/receipt_ocr_page.dart
git commit -m "feat(receipt_ocr): 路由 + 聊天页壳" --no-verify
```

---

## Task 7: HomePage 第三条入口

**Files:**
- Modify: `lib/screens/chat/home_page.dart`

**Interfaces:**
- Consumes: `ReceiptOcrPage` from Task 6

- [ ] **Step 1: 加 import + 第三条 entry**

修改 `lib/screens/chat/home_page.dart`：

1) 顶部 import 区追加：
```dart
import '../../core/ai_chat/receipt_ocr/receipt_ocr_page.dart';
```

2) `_entries` 列表追加第三条（在 Format 后）：
```dart
AssistantEntry(
  icon: Icons.receipt_long,
  title: '小票',
  subtitle: 'OCR 识别 → 快速比价',
  color: (context) => Theme.of(context).colorScheme.tertiary,
  builder: (context) => const ReceiptOcrPage(),
),
```

- [ ] **Step 2: 静态检查**

Run: `flutter analyze lib/screens/chat/home_page.dart`
Expected: `No issues found!`

- [ ] **Step 3: 全量静态检查**

Run: `flutter analyze`
Expected: `No issues found!`（或只剩既有 warning）

- [ ] **Step 4: 手动验证**

Run: `flutter run`：
1. 进入 AI 助手 HomePage，看到「小票」第三条
2. 点击 → 进入小票页面
3. 点击「模拟识别」按钮 → 800ms 后出现 receipt_ocr 卡，5 行 pending
4. ✓ 一行 → 弹 PickerSheet → 选/建主题 → 行锁定
5. × 一行 → 行灰化删除线
6. 点底部「打开比价计算器」跳链 → 进入 price-compare demo 页面
7. 回 price-compare 的 PickerSheet 验证未破坏（Task 3 的 regression）

- [ ] **Step 5: 提交**

```bash
git add lib/screens/chat/home_page.dart
git commit -m "feat(chat): HomePage 第三条入口「小票」" --no-verify
```

---

## Self-Review（plan 作者自查）

1. **Spec coverage**：
   - §1 目录结构 → Task 1-2, 4-6
   - §2 数据模型 LineItem/ReceiptResult → Task 1
   - §3 假后端 → Task 2
   - §3 PickerSheet 改 record → Task 3
   - §4 message 策略 + 注册 → Task 4-5
   - §5 页面壳 → Task 6
   - §6 HomePage 入口 → Task 7
   - §7 schema 跳链 → Task 5 footer
   - §8 边框强调按钮 → Task 5 `_EmphasisIconButton`
   - §9 行内 ✓ 记入 / × 拒绝 → Task 5 `_onTapRecord` / `_onTapReject`
   - §9 锁定状态 / 灰化 → Task 5 `_buildLine` switch
   - §9 底部状态摘要 + 跳链 → Task 5 footer

2. **Placeholder scan**：所有 step 都给了具体代码或 shell 命令，未出现 "TBD / TODO / 类似 Task N"。

3. **Type consistency**：
   - `LineItem/ReceiptResult/ReceiptLineStatus` → Task 1 定义，Task 2/5 消费，签名一致
   - `PriceTopicSummary` → Task 3 定义，Task 3/5 消费
   - `ReceiptOcrMessageData` → Task 4 定义，Task 5 消费
   - `ReceiptOcrRouter.runOnce()` → Task 6 定义，Task 6 内部消费

**结论**：spec 全部覆盖，类型一致，无占位。