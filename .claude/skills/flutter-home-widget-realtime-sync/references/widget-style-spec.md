# 桌面小组件样式规范(无 emoji · 支持 1×1 · launcher 兼容)

本 ref 沉淀自 `notion_widget` 桌面小组件的样式优化实战(2026-07)。
适用任何 Android AppWidget 的 layout + xml 资源配置。

## 何时读这个 ref

- 第一次为某个 widget 写 `widget_info.xml`(minWidth/minHeight/targetCell 配置)
- 修改 widget 样式(去 emoji、调字号、换 icon)
- 用户反馈"widget 太大"、"不支持 1×1"、"某些 launcher 看不到"
- 评估某个 widget 在不同 launcher 的兼容性

## 三条铁律(按重要性排序)

### 铁律 1:永远不要在 widget 内用 emoji

**OEM 字体不一致**会导致同一 emoji 在不同设备渲染成完全不同的图形,严重的甚至显示为豆腐块(□)。

```xml
<!-- ❌ 错误：emoji 在 MIUI / OneUI / EMUI 可能显示为方框或色块 -->
<TextView android:text="📷" android:textSize="20sp" />
<TextView android:text="📸" android:textSize="32sp" />
<TextView android:text="☀️" />  <!-- clock_widget 也踩了这个坑 -->
```

**替代方案**:
- **图形 icon** → 用 vector drawable,自己控制颜色和形状
- **文字说明** → 直接用中文/英文文字,所有 launcher 一致
- **状态符号** → 用 `?attr/colorPrimary` 或自定义 drawable,不用 emoji

#### A. Vector drawable 替代 emoji(本项目模式)

`res/drawable/notion_widget_icon.xml`:

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <!-- 相机机身 -->
    <path
        android:fillColor="#673AB7"
        android:pathData="M9,3 L7.5,5 L4,5 C2.9,5 2,5.9 2,7 L2,18
                          C2,19.1 2.9,20 4,20 L20,20 C21.1,20 22,19.1 22,18
                          L22,7 C22,5.9 21.1,5 20,5 L16.5,5 L15,3 L9,3 Z
                          M12,9 C14.21,9 16,10.79 16,13 C16,15.21 14.21,17 12,17
                          C9.79,17 8,15.21 8,13 C8,10.79 9.79,9 12,9 Z" />
    <!-- 镜头内圆 -->
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M12,11 C10.9,11 10,11.9 10,13 C10,14.1 10.9,15 12,15
                          C13.1,15 14,14.1 14,13 C14,11.9 13.1,11 12,11 Z" />
</vector>
```

引用方式:`android:src="@drawable/notion_widget_icon"`

#### B. 文字按钮替代 emoji 装饰

```xml
<TextView
    android:id="@+id/widget_capture_btn"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:gravity="center"
    android:text="拍照"
    android:textSize="14sp"
    android:textStyle="bold"
    android:textColor="#673AB7" />
```

### 铁律 2:支持 1×1 必须满足 manifest 三条件(全部)

**这是已知 launcher 兼容性硬约束**(Google Issue Tracker #296924921)。
单独改一个没用,必须三个一起改:

```xml
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="40dp"              <!-- ① 系统硬下限,不要再大 -->
    android:minHeight="40dp"
    android:minResizeWidth="40dp"
    android:minResizeHeight="40dp"
    android:targetCellWidth="1"          <!-- ② 明确目标 cell 数 -->
    android:targetCellHeight="1"
    android:updatePeriodMillis="1800000"
    android:initialLayout="@layout/your_widget"
    android:resizeMode="horizontal"      <!-- ③ 只允许横向 resize -->
    android:widgetCategory="home_screen">
</appwidget-provider>
```

#### 三条件详解

| 条件 | 取值 | 为什么 |
|------|------|--------|
| `minWidth/minHeight` | **40dp**(系统下限) | 设 70dp 在小 cell launcher(48-65dp)上被自动算成 2×1 |
| `targetCellWidth/Height` | **1** | 告诉 launcher "我希望默认是 1×1" |
| `resizeMode` | **`horizontal`**(只横向) | 设 `vertical` 会让 launcher 对高度做 "最低 2 row" 判定,直接过滤掉 1×1 候选 |

#### ⚠️ 已知 launcher 限制(无法完全解决)

**即使三个条件都满足,多数 launcher 仍会判定 widget 高度为 2 row**(这是 launcher 端硬约束)。
结果: widget picker 里看到的可能是 **1×2 占位**(1 列宽 × 2 行高),而不是真正 1×1。

| Launcher | 1×1 实际表现 |
|---------|-------------|
| Pixel Launcher | ✓ 完美支持 1×1 |
| Nova Launcher | ✓ 完美支持 1×1 |
| MIUI | ✗ 强制 1×2 占位 |
| OneUI | ✗ 强制 1×2 占位 |
| EMUI/HarmonyOS | △ 不一致,部分设备支持 |

**工程妥协方案**:接受 1×2 占位,layout 内按钮贴底部 + 顶部留白,视觉上"看起来小"。
真正需要纯 1×1 时,改用 **App Shortcuts**(长按应用图标弹菜单)替代 widget。

### 铁律 3:layout 必须 match_parent 自适应 1×1 ~ N×N

**绝不能用 `LinearLayout + wrap_content`**,小尺寸下被裁掉的部分**仍占行高**,widget 看起来偏大。

#### ✅ 推荐:FrameLayout + match_parent 核心交互元素

```xml
<FrameLayout
    android:id="@+id/widget_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@drawable/widget_background">

    <!-- 唯一交互元素,match_parent 撑满整个 widget -->
    <TextView
        android:id="@+id/widget_capture_btn"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:gravity="center"
        android:text="拍照"
        android:textColor="#673AB7"
        android:clickable="true"
        android:focusable="true"
        android:contentDescription="拍照并上传到 Notion" />
</FrameLayout>
```

**优势**:
- 1×1 时整个区域都是按钮(无需 header/hint 装饰)
- 拉到 2×2 时按钮仍居中(FrameLayout gravity center 自适应)
- 不依赖尺寸判断分支,代码逻辑单一

#### ❌ 反例:LinearLayout 多元素被裁切仍占空间

```xml
<!-- 1×1 时 header/hint 看不见但仍占行高 -->
<LinearLayout android:orientation="vertical" android:gravity="center">
    <LinearLayout android:id="@+id/widget_header">  <!-- 顶部 14dp 标题 -->
        <ImageView ... />
        <TextView android:text="Notion 图床" />
    </LinearLayout>
    <TextView android:id="@+id/widget_capture_btn" android:text="📸" />
    <TextView android:id="@+id/widget_hint" />     <!-- 底部 10dp 提示 -->
</LinearLayout>
```

**结果**: 1×1 高度仅 ~50dp 可用,但 LinearLayout 仍按 wrap_content 给 header/hint 留位,真正按钮被挤到中间一行。

## 修改 widget 后的强制操作

> ⚠️ **改完 manifest 后,桌面上已存在的旧 widget 不会自动刷新 metadata。**
> 必须长按删除,然后从 widget picker 重新添加。

不重新添加的话:
- launcher 用的是缓存的旧 minWidth/Height/targetCell 值
- 你看到的"没生效"实际上是 cache 在作祟
- 这是 Android 系统设计,不是 bug

## 完整示例:支持 1×1 ~ 2×2 的极简 widget

### `res/xml/notion_widget_info.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="40dp"
    android:minHeight="40dp"
    android:minResizeWidth="40dp"
    android:minResizeHeight="40dp"
    android:targetCellWidth="1"
    android:targetCellHeight="1"
    android:updatePeriodMillis="1800000"
    android:initialLayout="@layout/notion_widget"
    android:resizeMode="horizontal"
    android:widgetCategory="home_screen">
</appwidget-provider>
```

### `res/layout/notion_widget.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/widget_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@drawable/widget_background">

    <TextView
        android:id="@+id/widget_capture_btn"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:gravity="center"
        android:text="拍照"
        android:textSize="14sp"
        android:textStyle="bold"
        android:textColor="#673AB7"
        android:clickable="true"
        android:focusable="true"
        android:contentDescription="拍照并上传到 Notion" />

</FrameLayout>
```

### `res/drawable/notion_widget_icon.xml`(可选装饰)

参见上文铁律 1 的 vector 例子。

## 错误案例(本实战踩坑)

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 在 widget 里用 emoji (📷 📸 ☀️ 🌙) | MIUI/EMUI 等字体可能渲染成方块或不一致图形 | vector drawable 或纯文字替代 |
| `minWidth/minHeight` 设 70dp 想支持 1×1 | 小 cell launcher(48-65dp)自动算成 2×1 占位 | 改回系统下限 40dp |
| `resizeMode="horizontal\|vertical"` 想让用户自由 resize | launcher 对高度做 "最低 2 row" 判定,1×1 候选被过滤 | 只设 `horizontal` |
| LinearLayout 多元素 header/按钮/hint | 1×1 时被裁掉的部分仍占行高,widget 看起来偏大 | FrameLayout + match_parent 单一交互元素 |
| 改完 manifest 不删旧 widget 实例 | launcher 继续用缓存的旧 metadata,看不到新效果 | 长按删除后重新添加 |
| 想做真正 1×1 跨 launcher 兼容 | MIUI/OneUI launcher 端硬约束,manifest 改再多也没用 | 接受 1×2 占位,layout 视觉居中 |

## 验证清单

修改 widget 样式后,按序检查:

- [ ] **去 emoji**: grep `grep -E "[☀-➿]" res/layout/*.xml` 应无 emoji 字符
- [ ] **minWidth/Height ≤ 40dp**: 必须等于系统下限
- [ ] **resizeMode 不含 vertical**(若要支持 1×1)
- [ ] **layout 是 FrameLayout + match_parent**(若是单交互按钮)
- [ ] **装机后从 widget picker 添加新 widget**,验证 1×1 占位
- [ ] **长按删除旧 widget** 验证缓存不会干扰
- [ ] **目标 launcher 列表**(至少测 MIUI/OneUI/Pixel 中一个)