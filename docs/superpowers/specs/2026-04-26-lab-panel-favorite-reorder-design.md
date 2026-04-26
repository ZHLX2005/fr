# LAB Panel Favorite Icons 拖拽排序设计

## 概述

为 LAB Panel 的 favorite demo icons 添加长按拖拽排序功能，排序结果持久化到 SharedPreferences。

## 数据层修改

### 1. LabCardProvider 变更

**新增常量**
```dart
static const String _favoritesOrderKey = 'lab_card_favorites_order';
```

**新增字段**
```dart
final List<String> _favoritesOrder = [];  // 有序列表，存储 demo title
```

**新增方法**

| 方法 | 签名 | 说明 |
|------|------|------|
| `getFavoritesOrder` | `List<String> getFavoritesOrder()` | 返回有序列表 |
| `reorderFavorites` | `Future<void> reorderFavorites(List<String> ordered)` | 更新排序并持久化 |
| `syncFavoritesOrder` | `Future<void> syncFavoritesOrder()` | 同步：清理 order 中不在 favorites 的项 |

**现有方法修改**

| 方法 | 修改 |
|------|------|
| `setFavorite(title, true)` | 添加到 favorites 后，调用 `syncFavoritesOrder()` 确保 order 同步 |
| `setFavorite(title, false)` | 移除后，调用 `syncFavoritesOrder()` 清理 order |
| `_loadData()` | 同时加载 `_favoritesOrder` 列表 |
| `_saveFavorites()` | 不再需要，删除或保留兼容 |

### 2. 存储格式

```
Key: lab_card_favorites_order
Value: JSON array of strings, e.g. ["DemoA", "DemoB", "DemoC"]
```

## UI 层修改

### panel_content.dart

**导入**
```dart
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:flutter/services.dart';
```

**替换 GridView 为 ReorderableBuilder**

```dart
// 修改前
GridView.builder(
  shrinkWrap: true,
  physics: const NeverScrollableScrollPhysics(),
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 4,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    childAspectRatio: 0.92,
  ),
  itemCount: favoriteDemos.length,
  itemBuilder: (context, index) {
    final demo = favoriteDemos[index];
    return _FavoriteDemoShortcut(
      demo: demo,
      onTap: () => widget.onDemoTap(demo),
    );
  },
)

// 修改后
ReorderableBuilder<String>.builder(
  longPressDelay: const Duration(milliseconds: 300),
  onDragStarted: (index) => HapticFeedback.lightImpact(),
  onUpdatedDraggedChild: (index) {},
  onDragEnd: (index) {},
  onReorder: (reorderFn) {
    final reorderedTitles = reorderFn(favoriteTitles);
    _provider.reorderFavorites(reorderedTitles);
  },
  itemCount: favoriteTitles.length,
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
      itemCount: favoriteTitles.length,
      itemBuilder: (context, index) {
        final title = favoriteTitles[index];
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

**辅助方法**

```dart
List<String> get favoriteTitles {
  return _provider.getFavoritesOrder().where((title) {
    return widget.demos.any((e) => e.value.title == title);
  }).toList();
}

DemoPage _findDemoByTitle(String title) {
  return widget.demos.firstWhere((e) => e.value.title == title).value;
}
```

## 交互流程

```
1. 用户长按 favorite icon (300ms)
2. HapticFeedback.lightImpact() 触感反馈
3. 开始拖拽，icon 跟随手指移动
4. 拖动到目标位置后松手
5. ReorderableBuilder.onReorder 回调
6. 调用 _provider.reorderFavorites(newOrder)
7. Provider 更新 _favoritesOrder 并持久化
```

## 关键实现细节

### 1. Item Key
```dart
key: ValueKey(demo.title)
```
使用 title 作为稳定 key，避免 build 重建导致拖拽异常。

### 2. favoriteTitles 过滤逻辑
排序列表可能包含已删除/不存在的 demo，过滤后只显示当前仍为 favorites 的项。

### 3. 初始状态
如果 `_favoritesOrder` 为空（首次加载），按现有 `getFavorites()` 顺序作为初始顺序。

## 错误处理

| 场景 | 处理 |
|------|------|
| 加载时 favoritesOrder 数据损坏 | 降级为空列表，正常显示 |
| 拖拽时数据源为空 | GridView 正常显示空状态（由外层控制） |
| 同步时发现 title 映射不到 demo | 过滤掉该项 |

## 依赖

```yaml
dependencies:
  flutter_reorderable_grid_view: ^最新版本  # 已在项目中使用
```

无需新增依赖。
