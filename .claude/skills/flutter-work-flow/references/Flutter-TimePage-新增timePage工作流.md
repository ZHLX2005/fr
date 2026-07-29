# Flutter-TimePage — 新增 timePage 工作流

> ref：添加一个新 demo 并让它出现在 Focus 主页入口。**先读 `Flutter-TimePage-Focus时间模块设计` § 2-3 再看本 ref**。

## 触发场景

> 关键词：加新 time 工具 / 加新 timePage demo / 给 Focus 主页添入口 / 加新时间工作流。

只适用**新增一个 demo 并接入 time 体系**。改既有 demo / 改主页布局 / 改统计维度 不属于本 ref。

## 3 步 SOP

> 与 `lib/core/focus/time_tools/const_time_pages.dart` 文件顶部注释同源。

### 第 1 步：在 demo 类上声明 timePage

打开 `lib/lab/demos/<new_demo>.dart`，找到 DemoPage 子类，紧跟 `slug` 声明下方加：

```dart
@override
bool get timePage => true;
```

紧贴 slug 是惯例——一起 code review 时一眼看到所有 metadata。

### 第 2 步：在 `kTimePageMeta` 登记展示元数据

打开 `lib/core/focus/time_tools/const_time_pages.dart`，在 map 里**按 slug**（与第 1 步完全一致）追加：

```dart
'<your-slug>': TimePageMeta(
  label: '中文短标',         // 覆盖 demo.title（如 'Clock' → '时钟'）
  icon: Icons.<x>,
  color: Color(0xFF<hex>),   // 取 focus 莫兰迪调色板
  featured: false,           // 只有「精选大卡」位才 true
),
```

4 字段含义：
- `label` — 中文短标，最终在卡片显示。**不是 demo.title**（demo.title 是英文 slug-title 镜像）。
- `icon` — 卡片主图标。
- `color` — 强调色；当前调色板：`0xFFB5C9A3` sage / `0xFF6B9DFC` blue / `0xFFB39EB5` mauve / `0xFF8B9DC3` slate-blue 等。
- `featured` — **最多 1 个 demo 设 true**。当前 `clock` 占着，新 demo 默认 `false`。

⚠️ 不登记会怎样：`FocusHomePage` 用 `where(kTimePageMeta.containsKey)` 过滤，**未登记的 timePage demo 不会出现在主页**（但仍会在 Lab 列表里 —— 因为 Lab 过滤只查 `timePage` 不查 kTimePageMeta）。这是当前设计的预期行为：未登记 = 隐藏但仍进 Lab。

### 第 3 步：跑测试 + analyze + 提交

```bash
flutter analyze lib/core/focus/ lib/lab/
flutter test test/core/focus/const_time_pages_test.dart
flutter test test/lab/demo_slug_test.dart
```

测试断言：
- `const_time_pages_test.dart` 第 1 个测试：「`kTimePageMeta` 涵盖期望的 3 个 slug」—— **必须更新它的 `containsAll` 列表** 加你的 slug，否则测试挂红。
- `demo_slug_test.dart`：「slug 纯 ASCII」—— slug 不能含中文。
- 「新增 demo 后 `_demos.length >= 35`」这条得看基准值变化。

**autocommit on fix 后再补 commit**（项目惯例）。

## 自动接线机制：无需手动接 Focus 主页

`FocusHomePage._openDemo(slug)` 通过 `demoRegistry.getBySlug(slug)` 自动拿 demo 实例并 push `DemoDetailPage(demo)`。**无需 import 你的新 demo 类**，demo 注册进 `demoRegistry` 后即自动出现在主页。

路由可达性自动满足：`fr://lab/demo/<slug>` 由 `LabDemoHandler` 处理（`lib/core/schema/handlers/lab_demo_handler.dart`），不查 timePage 标记，所以无论 timePage true/false 路由都可达——这是 desktop widget 深链的硬要求。

## 正反例

### ✅ DO

```dart
// 拷贝已有 demo 作为模板（clock_demo.dart / calendar_demo.dart）
class MyToolDemo extends DemoPage {
  @override String get title => '我的工具';
  @override String get slug => 'my-tool';           // 纯 ASCII
  @override String get description => '一句话';
  @override bool get timePage => true;               // ← 第 1 步
  @override Widget buildPage(BuildContext context) { ... }
}

// kTimePageMeta 里：
'my-tool': TimePageMeta(
  label: '我的工具',
  icon: Icons.build_outlined,
  color: Color(0xFFB39EB5),  // 调色板内的颜色
),
```

### ❌ DON'T

| 反模式 | 后果 | 正确做法 |
| --- | --- | --- |
| 在 `lib/core/focus/` 里新建 `xxx_page.dart` 然后在 `FocusHomePage` import | 破坏 gamecenter 对称模型；fr:// 路由失效；Lab 不显示 | 永远走 demo 注册 |
| `featured: true` 给多个 demo | `featured.first` 非确定，抓哪个看 map 插入顺序 | 1 个即可；多精选属设计变动，先和用户确认 |
| 用中文 slug（`我的工具`） | demo_slug_test 必报 ASCII 错误；fr:// URI 解析崩溃 | 永远纯 ASCII 短词 |
| 在 `FocusHomePage` 用 `if (slug == '...') special-handling` 走分支 | 重复逻辑：让 featured 标识承担所有 hot path 选择 | 改 kTimePageMeta 的 `featured` 字段或加新字段 |
| 跳过 `const_time_pages_test.dart` 第 1 个测试更新 | 新 slug 没被断言 → 后续维护者不知你没登记 | 永远同步更新测试期望 |

## 易错 & 自检清单

> 完成 3 步后 grep 这 4 串字符串验证：

```bash
grep -rn "timePage" lib/lab/demos/<new>.dart        # 应该有 override
grep -rn "<new-slug>" lib/core/focus/time_tools/    # 应该在 kTimePageMeta
grep -rn "<new-slug>" test/core/focus/const_time_pages_test.dart  # 测试期望
flutter analyze lib/core/focus/ lib/lab/ && echo OK
```

若任一 grep 失败 / analyze 出错，回看「3 步 SOP」定位。
