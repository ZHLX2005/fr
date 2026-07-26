# Flutter 游戏中心 — 扩展游戏路线

> 何时读：**往游戏中心加一款新游戏 / 加新分类 / 加新封面图案** 时。
> 本 ref 回答"改哪里、按什么顺序、怎么验证"。
>
> 对应代码：`lib/screens/profile/lab/game_center/`（const/artwork/cards 三件套）
> + 宿主 `game_center_page.dart`。架构原理见 [[Flutter-Lab容器-模块结构与重构模式]]。

---

## 数据流：从注册到封面的一条链

```
lib/lab/demos/xxx_demo.dart       override DemoType get type => game  +  get slug
        ↓ lab/lab_bootstrap.dart  registerXxxDemo()
demoRegistry.getAll().filterByType(game)        ← GameCenterPage initState 去重缓存
        ↓
  _featured = games.where(meta.isOnline)        → 精选横滑（仅"全部"tab 出现）
  _bucket(cat) = games.where(meta.categories∋cat) → 分类分桶
        ↓
GameGridCard / GameFeaturedCard → gameMetaOf(demo.slug) → GameArtwork
```

常量层按 **slug** 判归属（不 `is DemoClass`），所以 `const_game_center.dart`
零依赖任何 demo 实现——加删游戏不动 import 图。

## 封面三级来源（按优先级自动降级）

| 级 | 来源 | 谁设置 | 落点 |
|---|---|---|---|
| 1 | 用户自定义背景图 `LabCardProvider.getBackground(title)` | 长按 Lab 卡设图 | `game_center_cards.dart` → `DemoCoverImage` |
| 2 | 程序化封面 `GameMeta.gradient` + `.pattern` + `.icon` | 登记在 `kGameMeta` | `game_center_artwork.dart` `GameArtwork` |
| 3 | fallback `kFallbackGameMeta`（灰+game图标+arcade） | 自动 | `const_game_center.dart` |

## 扩展点地图

| 做什么 | 改哪里 | 备注 |
|---|---|---|
| 加一款游戏 | `demos/xxx_demo.dart` + `lab_bootstrap.dart` | 必改：①`type=>game` ②`registerXxx()` |
| 登记封面/分类 | `const_game_center.dart` 的 `kGameMeta` | 建议必做，否则走 fallback |
| 加全新分类 | `const_game_center.dart` | `GameCategory` + `kGameCategoryTabs` + `kGameCategoryIcons` + `kGameCategoryLabels` 各加一行 |
| 加封面图案 | `const_game_center.dart` + `game_center_artwork.dart` | `GameArtPattern` enum + `_ArtPatternPainter._paintXxx` + switch |

## 加新游戏 SOP

```dart
// 1) demos/gomoku_lua_demo.dart
class GomokuLuaDemo extends DemoPage {
  @override String get slug => 'gomoku-lua';            // ← 与 kGameMeta key 严格一致
  @override DemoType get type => DemoType.game;         // ← 进游戏中心的开关
  ...
}

// 2) lab/lab_bootstrap.dart
import 'demos/gomoku_lua_demo.dart' show registerGomokuLuaDemo;
... registerGomokuLuaDemo();

// 3) game_center/const_game_center.dart — kGameMeta
'gomoku-lua': GameMeta(
  categories: {GameCategory.multiplayer, GameCategory.board}, // 多归属
  icon: Icons.grid_4x4_rounded,
  gradient: [Color(0xFF0F766E), Color(0xFF14B8A6)],
  mode: '联机双人',           // 卡片副标题 + 精选胶囊文案
  pattern: GameArtPattern.grid,
),
```

验证：`flutter analyze` 0 error → 真机确认精选横滑只含联机、分类 tab 数量对、封面不白板。

## 真坑

| 坑 | 现象 | 预防 |
|---|---|---|
| slug 拼错 | `gameMetaOf()` 查不到不报错 → 封面静默走 fallback（灰底） | key 必须与 `DemoPage.slug` 逐字符一致，登记后肉眼对一遍 |
| 忘 `type=>game` | 游戏进了 Lab 列表，不在游戏中心 | demo 必须标 type |
| 忘 `registerXxx()` | 游戏完全不出现 | bootstrap 两处都要（import + 调用） |
| 收藏/背景 key 用 title | 改 demo 标题 = 用户收藏与自定义封面静默丢失 | 已知债务，改 provider 前先看 |
| 别名 slug 重复渲染 | 一 demo 多 slug → 列表重复卡片 | page 已按实例去重；新代码别绕过去重直接用 getAll() |
| 联机游戏不进精选 | `isOnline` 看 categories 是否含 multiplayer | 精选 = `_games.where(isOnline)`，本地游戏不进 |
