# LAB Panel Favorite Icons 拖拽排序实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 LAB Panel 的 favorite demo icons 添加长按拖拽排序功能，排序结果持久化到 SharedPreferences。

**Architecture:** 在 LabCardProvider 中新增有序列表存储排序顺序，UI 层使用 ReorderableBuilder 包装 GridView 实现拖拽。

**Tech Stack:** Flutter, SharedPreferences, flutter_reorderable_grid_view

---

## 文件映射

| 文件 | 改动 |
|------|------|
| `lib/lab/providers/lab_card_provider.dart` | 修改：新增 _favoritesOrder 字段、getFavoritesOrder/reorderFavorites/syncFavoritesOrder 方法、修改 setFavorite/_loadData |
| `lib/screens/lab/lab_page/panel_content.dart` | 修改：导入、替换 GridView 为 ReorderableBuilder、添加辅助方法 |

---

## 任务列表

### Task 1: LabCardProvider 数据层修改

**Files:**
- Modify: `lib/lab/providers/lab_card_provider.dart`

- [ ] **Step 1: 添加 _favoritesOrderKey 常量**

在 `lab_card_provider.dart` 第6行后添加：
```dart
static const String _favoritesOrderKey = 'lab_card_favorites_order';
```

- [ ] **Step 2: 添加 _favoritesOrder 字段**

在 `_favorites` 字段下方添加：
```dart
final List<String> _favoritesOrder = [];
```

- [ ] **Step 3: 添加 getFavoritesOrder 方法**

在 `getFavorites()` 方法后添加：
```dart
List<String> getFavoritesOrder() {
  if (_favoritesOrder.isEmpty) {
    return _favorites.toList()..sort();
  }
  return List<String>.from(_favoritesOrder);
}
```

- [ ] **Step 4: 添加 reorderFavorites 方法**

在 `setFavorite` 方法后添加：
```dart
Future<void> reorderFavorites(List<String> ordered) async {
  _favoritesOrder
    ..clear()
    ..addAll(ordered);
  await _saveFavoritesOrder();
  notifyListeners();
}
```

- [ ] **Step 5: 添加 syncFavoritesOrder 方法**

在 `reorderFavorites` 方法后添加：
```dart
Future<void> syncFavoritesOrder() async {
  _favoritesOrder.removeWhere((title) => !_favorites.contains(title));
  await _saveFavoritesOrder();
}
```

- [ ] **Step 6: 添加 _saveFavoritesOrder 方法**

在 `_saveBackgrounds` 方法后添加：
```dart
Future<void> _saveFavoritesOrder() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(_favoritesOrderKey, _favoritesOrder);
}
```

- [ ] **Step 7: 修改 _loadData 方法**

在 `_loadData()` 方法中，加载 favorites 之后添加：
```dart
final favoritesOrder = prefs.getStringList(_favoritesOrderKey);
_favoritesOrder
  ..clear()
  ..addAll(favoritesOrder ?? const <String>[]);
```

- [ ] **Step 8: 修改 setFavorite 方法**

在 `setFavorite` 方法中，无论添加还是移除后，都调用 `syncFavoritesOrder()`：
```dart
Future<void> setFavorite(String demoTitle, bool value) async {
  if (value) {
    _favorites.add(demoTitle);
  } else {
    _favorites.remove(demoTitle);
  }
  await syncFavoritesOrder();
  notifyListeners();
}
```

- [ ] **Step 9: 提交 Task 1**

```bash
git add lib/lab/providers/lab_card_provider.dart
git commit -m "feat(lab): 添加 favorites 排序持久化支持"
```

---

### Task 2: panel_content.dart UI 层修改

**Files:**
- Modify: `lib/screens/lab/lab_page/panel_content.dart`

- [ ] **Step 1: 添加导入**

在文件顶部添加：
```dart
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:flutter/services.dart';
```

- [ ] **Step 2: 添加辅助属性**

在 `_LabPanelContentState` 类中，`favoriteDemos` 过滤逻辑后添加：
```dart
List<String> get _favoriteTitles {
  final order = _provider.getFavoritesOrder();
  return order.where((title) {
    return widget.demos.any((e) => e.value.title == title);
  }).toList();
}

DemoPage _findDemoByTitle(String title) {
  return widget.demos.firstWhere((e) => e.value.title == title).value;
}
```

- [ ] **Step 3: 替换 GridView 为 ReorderableBuilder**

找到第89-107行的 GridView.builder，替换为：
```dart
ReorderableBuilder<String>.builder(
  longPressDelay: const Duration(milliseconds: 300),
  onDragStarted: (index) => HapticFeedback.lightImpact(),
  onUpdatedDraggedChild: (index) {},
  onDragEnd: (index) {},
  onReorder: (reorderFn) {
    final reorderedTitles = reorderFn(_favoriteTitles);
    _provider.reorderFavorites(reorderedTitles);
  },
  itemCount: _favoriteTitles.length,
  childBuilder: (itemBuilder) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.92,
      ),
      itemCount: _favoriteTitles.length,
      itemBuilder: (context, index) {
        final title = _favoriteTitles[index];
        final demo = _findDemoByTitle(title);
        return itemBuilder(
          _FavoriteDemoShortcut(
            key: ValueKey(title),
            demo: demo,
            onTap: () => widget.onDemoTap(demo),
          ),
          index,
        );
      },
    );
  },
)
```

- [ ] **Step 4: 提交 Task 2**

```bash
git add lib/screens/lab/lab_page/panel_content.dart
git commit -m "feat(lab): 使用 ReorderableBuilder 实现 favorite icons 拖拽排序"
```

---

## 自检清单

- [ ] Spec 覆盖完整：数据层 + UI 层都有对应任务
- [ ] 无 placeholder：所有代码都是完整实现
- [ ] 类型一致性：_favoritesOrder 是 List<String>，方法签名与 spec 一致
- [ ] Task 依赖：Task 2 依赖 Task 1（需先完成数据层修改）

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-26-lab-panel-favorite-reorder-plan.md`**

Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
