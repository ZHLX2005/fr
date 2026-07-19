# Flutter DemoPage slug 抽象化与别名机制

> 何时读：要把 `kDemoSlugs` 全局表迁到 `DemoPage.slug` 抽象字段时、要给某个 demo 注册多个 fr:// slug 别名时、或要合并多个相关 demo 为统一 Tab 容器时。

---

## slug 抽象化改造

### 背景

`lib/lab/lab_container.dart` 原本有一张 `kDemoSlugs` 全局 map：

```dart
const Map<String, String> kDemoSlugs = {
  '时钟': 'clock',
  'Rive 摆钟': 'rive-pendulum',
  ...
};
```

`DemoPage.slug` 默认实现查这个 map：

```dart
String get slug => kDemoSlugs[title] ?? title;
```

### 问题

| 问题 | 影响 |
|------|------|
| 加新 demo 要改 2 个文件 | demo 文件 + lab_container.dart 的 map 行 |
| 漏改 map 编译期无报错 | 直到运行 / slug 测试才发现 |
| slug 和 title 相距 30+ 文件 | review 时容易漏 |
| map 是「特殊映射」的容器（如 `'Demo 实验室' → 'demo-lab'`），但实际 90% 是 1:1 直接对应 | 过度抽象 |

### 改造方案（已完成 2026-07）

把 `DemoPage.slug` 改为 abstract getter，每个子类自带：

```dart
// lib/lab/lab_container.dart
abstract class DemoPage {
  String get title;
  String get description;
  String get slug;          // ← abstract，强制每个子类声明
  Widget buildPage(BuildContext context);
  // ...
}
```

```dart
// 每个 demo 文件
class ClockDemo extends DemoPage {
  @override String get title => '时钟';

  @override String get slug => 'clock';      // ← 与 title 同文件 co-located

  @override String get description => '...';
  // ...
}
```

**删除** `kDemoSlugs` 全局 map。

### 迁移清单（一次性，36 个 demo）

每个 demo 文件加：
```dart
@override
String get slug => '<slug>';
```

插在 `String get title` 之后、`String get description` 之前。

### 迁移结果

| 维度 | 之前 | 之后 |
|------|------|------|
| 加新 demo 改文件数 | 2（demo + lab_container） | 1（仅 demo） |
| 漏写 slug 检测时机 | 测试阶段 / 运行期 | **编译期**（abstract 强制） |
| slug 测试断言 | 间接：查 map + demo.title | 直接：读 `DemoPage.slug` 字段 |
| 旧 demo 是否需要立即补 slug | — | ✅ 改造前**所有** demo 必须补，否则编译失败 |

---

## Demo 别名机制（slug 重定向）

### 场景

合并多个 demo 后（如 `Rive 摆钟` + `Rive 数据绑定` + `Demo 实验室` → `Rive 演示`），
旧的 fr:// 链接（`fr://lab/demo/rive-pendulum` 等）会 404。

### 解决：`demoRegistry.register(demo, key: alias)`

```dart
class RiveDemo extends DemoPage {
  @override String get slug => 'rive-demo';     // 主 slug
  ...
}

void registerRiveDemo() {
  final demo = RiveDemo();
  demoRegistry.register(demo, key: 'rive-demo');           // 主
  demoRegistry.register(demo, key: 'rive-pendulum');       // 别名
  demoRegistry.register(demo, key: 'rive-data-bind');      // 别名
  demoRegistry.register(demo, key: 'demo-lab');            // 别名
}
```

`_bySlug` map 的 key 不同但 value 指向**同一** DemoPage 实例。

### 别名一致性测试

```dart
test('aliases resolve to same instance', () {
  final main = demoRegistry.getBySlug('rive-demo')!;
  expect(demoRegistry.getBySlug('rive-pendulum'), same(main));
  expect(demoRegistry.getBySlug('demo-lab'), same(main));
});
```

`same(x)` 是引用相等断言，比 `equals` 严格——确保别名真的指向同一对象，不是两个内容相同但独立的对象。

### 别名机制 vs slug 字段

| 维度 | DemoPage.slug | register(key:) 别名 |
|------|---------------|---------------------|
| 数量 | 每个 demo 1 个 | 每个 demo 可有 N 个 |
| 用途 | 「我是谁」 | 「我还兼容哪些旧 URL」 |
| 旧 slug 兼容 | 不支持 | ✅ |
| 必须纯 ASCII | ✅ | ✅ |

---

## 多个相关 demo 合并为统一 Tab 容器

### 何时合并

- 多个 demo 都属于同一技术主题（如 Rive 的 3 种用法：摆钟 / 数据绑定 / 实验室）
- 单 demo 内容较薄（< 150 行）但 demo 数量膨胀 lab 菜单
- 想统一展示同一资源库的多种使用方式

### 目录组织（方案 A）

```
lib/lab/demos/rive_demo/                    # 统一 demo 目录
├── rive_demo.dart                          # 入口 DemoPage + TabBar 容器
├── const_rive.dart                         # 共享常量：asset 路径、tab key、参数
├── rive_pendulum_view.dart                 # 子页 1
├── rive_data_bind_view.dart                # 子页 2
├── rive_lab_view.dart                      # 子页 3
└── rive_error_view.dart                    # 共享错误视图（消除 3 处重复）
```

- 单文件过大才用方案 A（默认阈值 400 行；本项目 Rive 合并 3 个 demo ≈ 1100 行 → 必须方案 A）
- 共享 widget（错误视图、状态 chip）提到目录根，作为 sibling view 文件
- 常量统一到 `const_xxxx.dart`（flutter-work-flow 主 SKILL 规范要求）

### 入口 DemoPage + TabBarView 模式

```dart
class RiveDemoPage extends StatefulWidget { ... }

class _RiveDemoPageState extends State<RiveDemoPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Text('Rive 演示', style: ...),              // 统一标题
            TabBar(controller: _tabController, tabs: ...),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  RivePendulumView(),
                  RiveDataBindView(),
                  RiveLabView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Tab key 枚举

```dart
// const_rive.dart
enum RiveDemoTab {
  pendulum, dataBind, lab;

  String get label => switch (this) { ... };
  String get slug => switch (this) { ... };   // 旧 slug 别名映射
}
```

### 删除旧 demo 文件

迁移后必须删除旧单文件 demo：

```bash
rm lib/lab/demos/rive_pendulum_demo.dart \
   lib/lab/demos/rive_data_bind_demo.dart \
   lib/lab/demos/demo_laboratory_demo.dart
```

`lib/lab/lab_bootstrap.dart` 同步清理 import + `registerXxxDemo()` 调用。

---

## 相关 ref

- fr:// 路由总设计：`Flutter-自定义Scheme路由中心化-fr-Router`
- fr:// 日常使用 / 加新 demo：`Flutter-fr路由-注册规范与防腐蚀`
- Rive demo 完整流程：`rive-skills/references/flutter-project-workflow`
- Rive 0.14.x API / DataBind：`rive-skills/references/flutter-databind-0.14`

---

## 踩坑记录

### 坑 1：Agent 批量改文件时可能 revert 不该 revert 的文件

派 Agent 改 36 个 demo 加 slug 字段时，Agent 在 diff 检查后「恢复意外的 lab_container.dart 变更」——但那正是主代理故意改的（删 `kDemoSlugs`）。

**预防**：
- 派 Agent 改文件前**先记录**主代理自己已改的文件清单（`git status` 输出快照）
- Agent 完成后**主代理亲自**重新应用关键文件改动
- 给 Agent 的 prompt 写明「不要碰文件 X / Y / Z」

### 坑 2：flutter analyze exit code 误判

```bash
flutter analyze 2>&1 | grep -E "^\s+error"
# 退出码 = 1（grep 无匹配），但被误以为「analyze 失败」
```

**正确判断方式**：
```bash
flutter analyze 2>&1 | grep -E " error "          # 前后带空格，匹配 issue 行
flutter analyze 2>&1 | tail -3                     # 看最后一行总结
```

`flutter analyze` 在 **0 issue 时** 退出码 = 0，**有 issue 时** 退出码 = 1（但仍打印 issue 详情）。
真正想「只看 issue」应该用 `grep -E " error | warning "` 拿 issue 行。

### 坑 3：`.gitignore` 拒绝 add 已追踪文件

本项目 `.gitignore` 写：
```
test/*
!test/core/
!test/core/localnet/
```

意图：`test/lab/` 是本地实验，不入版本库。
但已存在的 `test/lab/demo_slug_test.dart` **不受影响**（gitignore 只忽略未追踪文件）。

**判断文件是否被 ignore**：
```bash
git check-ignore -v <file>
# exit 0 + 打印规则 = 被忽略
# exit 1 = 不被忽略（已追踪 或 不匹配规则）
```

### 坑 4：slug 测试只检查长度下限不检查上限

之前：
```dart
expect(all.length, greaterThanOrEqualTo(37));
```

合并 3 个 demo → 实际只有 35 个，仍 `≥ 37` 不成立 → 测试 fail。
但**反过来**：漏注册 demo 让总数小于实际期望，测试也 fail——这是好事。

**问题**：测试没断言「**正好** N 个 demo」，漏注册和重复注册都可能逃过。
**改进方向**：用 `expect(all.length, equals(N))` 替代 `>= N`，但 N 需要随 demo 数量动态维护（容易遗忘更新）。

当前采用折中：`>= 35`（合并后实际数）+ 保留「slug 纯 ASCII」核心断言。