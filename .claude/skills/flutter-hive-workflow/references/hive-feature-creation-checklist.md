# 创建带 Hive 存储的新模块 · Checklist

> **何时读**：要新增一个模块（功能/特性/页面），并希望它**立刻出现在 `Lab → 存储分析` 面板里、可观察、可管理（清空/删除）**，同时**避免主题/颜色/标签在多个文件里散落**。
>
> 配套 SKILL：`[[flutter-hive-workflow]]` 的「添加一个自定义 Type 的 Hive 存储」6 步流程。**本 ref 解决的是"创建时如何保持一致性"**，SKILL 解决的是"创建流程本身"。

---

## 0. 一句话原则

> **BoxDescriptor 的 formatValue/displayName/typeId 是面板展示的唯一数据源。**
> 你的模块只要 register 一次，面板就自动有 —— **永远不要改 `storage_analyze_demo.dart`**。

---

## 1. 避免主题散落 · 5 条铁律

| 铁律 | 怎么做 | 错误示范 |
|---|---|---|
| **displayName 集中到 `xxx_meta.dart`** | `static const String displayName = '我的功能';` | `'我的功能'` / `'功能模块'` / `'功能'` 在多个 widget 重复 |
| **formatValue 只返回 String** | `formatValue: (v) => '内容: ${...}'` | `formatValue: (v) => Container(color:..., ...)` 渲染 widget |
| **formatValue 不写硬编 hex** | 走 `Theme.of(context).colorScheme` 或 `xxxColors.xxx` | `Color(0xFF6B7280)` 散落 |
| **formatValue > 5 行 → 拆 `xxx_formatter.dart`** | 单独 helper，register 引用 | 把巨函数内联在 register() 里 |
| **typeId 走 `HiveTypeIds.xxx` 常量** | `static const int myFeature = 92;` | `@HiveType(typeId: 92)` 魔法数字 |

---

## 2. 完整范本（可直接套用）

### Step 1：分配 typeId
```dart
// lib/core/storage/hive_type_ids.dart 内追加
static const int myFeature = 92;  // core 0-9 / lab 80-99
```

### Step 2：集中常量
```dart
// lib/core/my_feature/my_feature_meta.dart
abstract final class MyFeatureMeta {
  static const String boxName = 'my_feature_box';
  static const String displayName = '我的功能';
}
```

### Step 3：Formatter 独立
```dart
// lib/core/my_feature/my_item_formatter.dart
import 'my_item.dart';
abstract final class MyItemFormatter {
  static String of(MyItem i) {
    return [
      '类别: ${_categoryLabel(i.category)}',
      '标题: ${i.title}',
      if (i.note != null) '备注: ${i.note}',
    ].join('\n');
  }
  static String _categoryLabel(MyItemCategory c) => switch (c) {
    MyItemCategory.work => '工作',
    MyItemCategory.life => '生活',
    _ => '其他',
  };
}
```

### Step 4：Repo（init 里 4 步标准动作）
```dart
// lib/core/my_feature/my_feature_repo.dart
import 'package:hive_flutter/hive_flutter.dart';
import '../storage/box_descriptor.dart';
import '../storage/hive_type_ids.dart';
import '../storage/storage_registry.dart';
import 'my_item.dart';
import 'my_item_formatter.dart';
import 'my_feature_meta.dart';

class MyFeatureRepo {
  late Box<MyItem> _box;
  bool _initialized = false;
  Future<void> init() async {
    if (_initialized) return;                                 // 1) init guard
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(HiveTypeIds.myFeature)) {  // 2) adapter guard
      Hive.registerAdapter(MyItemAdapter());
    }
    _box = await Hive.openBox<MyItem>(MyFeatureMeta.boxName);  // 3) 泛型 open
    StorageRegistry.register(BoxDescriptor<MyItem>(            // 4) 面板注册
      name: MyFeatureMeta.boxName,
      displayName: MyFeatureMeta.displayName,
      typeId: HiveTypeIds.myFeature,
      openTyped: () => Hive.openBox<MyItem>(MyFeatureMeta.boxName),
      formatValue: (v) => MyItemFormatter.of(v as MyItem),     // ← 单一真相源
    ));
    _initialized = true;
  }
  // 业务方法...
}
final myFeatureRepo = MyFeatureRepo();
```

### Step 5：main.dart 启动期
```dart
await myFeatureRepo.init();
```

### Step 6：验证
```bash
flutter analyze    # 0 error
flutter run        # Lab → 存储分析 → 你的 box 自动出现
```

---

## 3. 反模式 checklist（提交前自查）

- [ ] `formatValue` 没有 `Container` / `Row` / `TextStyle` / `Color(0xFF...)` 任何 widget/颜色硬编
- [ ] `formatValue` 没有 emoji 当"主题"（🔵✅）—— 视觉风格由面板统一提供
- [ ] `displayName` 来自 `MyFeatureMeta.displayName`，没有在其他文件重复写字符串
- [ ] `typeId` 引用 `HiveTypeIds.xxx` 常量，不是数字字面量
- [ ] `BoxDescriptor` 里的 boxName 引用 `MyFeatureMeta.boxName`，不是重复字符串
- [ ] 没有碰 `storage_analyze_demo.dart`（它自动出现）
- [ ] 没有碰 `storage_manager.dart`（它是纯查询代理）

---

## 4. 为什么"显示和管理"自动生效

`Lab → 存储分析` 通过 `StorageManager` 遍历 `StorageRegistry.all`：

```
StorageRegistry.all        ← 你的 BoxDescriptor 在这里
  ↓
StorageManager.getAllStorageInfo()
  ↓
面板展示：name / displayName / keyCount / size
  ↓
面板展开：formatValue(value) 把每条 value 转成 String
  ↓
面板操作：openTyped()/openUntyped() 提供 box 句柄做删除/清空
```

**你 register 一次 = 面板自动获得**：卡片 / keyCount / size / 展开后逐条格式化 / 删除按钮 / 清空按钮。**完全零代码改 `storage_analyze_demo.dart`**。

---

## 5. 管理操作的边界

面板支持的管理操作（**已经实现，不要重写**）：
- 清空整个 box（confirm dialog）
- 删除单条 key
- 展开/折叠每条 value
- 实时显示 keyCount / 字节大小

面板**不支持**的（如果你需要，自己做页面）：
- 编辑单条 value
- 跨 box 联合查询
- 导入/导出（已经有 `lib/core/storage/export/`，独立子系统）
