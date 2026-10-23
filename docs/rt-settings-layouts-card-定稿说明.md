# RT 设置页「就地管理」设计定稿（2026-10-23）

来源提案：A 枢纽卡 / B 布局中心 / C 就地管理 / D 偏好页 四选一 → **定 C**。
原型文件：temp/rt-settings-inline-final.html（可交互 mockup + 规格表）。
第一版「每布局一卡、卡内双栏」被否；修正为下述定稿。

## 定稿结构

布局区 = 一张大卡片：
- 上栏「竖屏」组列表，下栏「横屏」组列表，组间分隔带
- 可用性由分组表达（rtCanvasLayoutUsableIn 过滤组员）：写字不进横屏组；含 dpad/vpad/kb 的布局不进竖屏组；「置灰行」状态因此消失
- 双朝向布局（触控屏/自定义）两组各一行，数据本就按朝向各存锚点
- 行状态仅两态：使用中 ✓（每组恰一）/ 未激活 ○

## 交互（用户三条硬性要求）

1. 管理菜单只从行尾 ⋯ 打开，无长按手势
2. 无独立排序页：行首把手组内拖拽，两组各自独立（沿用面板 ReorderableListView 组内语义）
3. 点行 = 切该组激活（withActiveFor）；组头右侧「当前」回显

行菜单朝向随组而定（不再按朝向分组）：在画布上编辑（仅 RT 页入口，摆位编排在此完成）/ 恢复出厂摆放（仅内置）/ ── / 改名 / 删除（仅自定义）。
「模块编排」独立入口已裁撤（画布编辑态覆盖其职责），rt_canvas_module_page 退役。

## 边界

- 删除使用中自定义布局 → 该组激活回落默认（竖→写字 / 横→触控屏）
- 应用设置入口（无画布）：菜单隐藏「在画布上编辑」
- RT 页胶囊面板瘦身为「快切 + 管理布局…」，管理逻辑唯一落在设置页

## 落地（已实施 2026-10-23）

新增 `lib/core/remotetype/settings/rt_layouts_card.dart`（大卡 + 菜单）、`rt_layout_row_tile.dart`（行 + 徽）、
`rt_new_layout_row.dart`（新建虚线行 + 自绘虚线边框 + 选朝向对话框）、`rt_layout_dialogs.dart`（恢复出厂/改名/删除）；
重写 `rt_settings_page.dart`（删 ①⑦⑧⑨ 四段入口，布局区换成大卡 + 新建行；偏好区不动）；
删除 `rt_canvas_layouts_sheet.dart`（旧全功能管理面板，零引用退役）与 `rt_canvas_module_page.dart`（独立模块页退役）；
`rt_page.dart` 改编辑流；`rt_canvas_view.dart` 顶部注释更新为新落点。

胶囊快切面板 `ui/rt_layout_picker.dart` 已是终态（快切 + 设置入口），未动。

### 与原型的两处偏差

1. **内置布局不给改名**：沿用既有不变量「内置不可删、不可改名」（`rt_layout_ops.dart`），原型规则表写的是
   「可编辑布局可改名」。内置菜单 = 画布编辑 / 恢复出厂摆放；自定义 = 画布编辑 / 改名 / 删除。
2. **修了「在画布上编辑」的旧快照竞态**：原实现里 RT 页拿内存旧快照 `withActiveFor` 后回写磁盘，会抹掉设置页
   刚新建/改名的布局。现改为：设置页点「在画布上编辑」只记 id → 设置页关闭 → 先回读盘上最新 → 再执行编辑。

### 验证

- `flutter analyze lib/core/remotetype` 零问题；全仓 analyze 我改动的文件零问题
- `flutter test test/core/remotetype/` 142 例全绿
- 新增 `test/core/remotetype/rt_layouts_card_test.dart`（6 例：双组渲染 / 点行切激活带朝向 / 固定布局无 ⋯ /
  内置与自定义菜单内容 / 无画布入口隐藏画布编辑）
- 更新 `test/core/remotetype/rt_settings_page_test.dart`：大卡结构 + 落盘闭环（切激活 / 新建 / 改名 / 删除）
- 全量 `flutter test` 1251 通过 / 10 失败，失败全在 `test/api/notion/*`（缺 `NOTION_TOKEN` 等环境依赖）与本次改动无关


## 迭代史（5 轮）

R1 分卡双栏（被否）→ R2 大卡双组重构 → R3 状态语义简化（分组表达可用性）→ R4 菜单与细节（朝向随组、入口模拟）→ R5 落地对齐（符号映射、胶囊瘦身）。
