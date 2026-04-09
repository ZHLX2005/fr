# WordDrag 单词背记模块 - 设计规范

> 状态：**基础框架和动画已完备**  
> 更新时间：2026-04-09

---

## 一、产品愿景

WordDrag 是一个**基于滑动交互的背单词工具**。用户通过上下左右滑动卡片来对单词进行分类操作，模拟"抽认卡"（flashcard）的物理交互体验。

### 核心交互

| 滑动方向 | 操作 | 效果 |
|---------|------|------|
| 上滑 | 跳过 | 显示单词详情，然后进入下一个 |
| 左滑 | 稍后复习 | 单词移至列表末尾 |
| 右滑 | 已掌握 | 单词标记为 mastered |
| 下滑 | 分类模式 | 显示分类桶列表，拖入桶中分类 |

### 设计参考

基于 photoo NativeVoiceLikeActivity 的交互模型，使用 Spring Physics 模拟真实卡片弹性。

---

## 二、技术架构

### 文件结构

```
lib/core/word_drag/
├── word_drag.dart                    # 导出入口
├── models/
│   └── word.dart                    # 单词数据模型
├── pages/
│   ├── word_drag_page.dart          # 主页面（含 CategoryDropRow）
│   └── word_detail_page.dart        # 详情页（待完善）
├── providers/
│   ├── word_drag_state.dart         # 不可变状态数据类
│   ├── word_drag_notifier.dart      # ChangeNotifier 状态管理
│   └── draggable_word_card_controller.dart  # [废弃] 旧架构遗留
└── widgets/
    ├── draggable_word_card.dart     # 核心卡片组件（手势+动画）
    ├── word_card_content.dart       # 卡片内容展示
    └── category_drop_row.dart       # 分类桶行组件
```

### 架构原则

- **状态驱动**：`WordDragNotifier`（ChangeNotifier）管理所有状态，`WordDragPage` 为 ConsumerWidget
- **事件驱动**：手势事件通过回调传递到 Notifier，Notifier 更新状态后通知 UI 重建
- **物理动画**：`DraggableWordCard` 内部使用 `SpringSimulation` 实现弹性回弹效果

---

## 三、已完成功能（基础框架 + 动画）

### 3.1 DraggableWordCard（卡片拖拽核心）

**文件**：`widgets/draggable_word_card.dart`

**功能**：
- 四向滑动检测（阈值 160px）
- Spring 回弹动画（stiffness=2000, dampingRatio=0.85）
- 按压缩下效果（scale 1.0 → 0.96）
- 文件夹吸入动画（scale→0.1, alpha→0, 250ms）
- 卡片堆叠视觉效果（stackIndex 递减 scale 4%，Y 偏移 15px）
- Action Indicator 跟随显示

**常量**：
```dart
static const double _threshold = 160;           // 滑动确认阈值
static const double _folderModeThreshold = 300;  // 下滑进入文件夹模式
static const double _flingThreshold = 800;       // 快速滑动速度阈值
```

**回调接口**：
```dart
onSwipeLeft          // 左滑回调
onSwipeRight         // 右滑回调
onSwipeUp            // 上滑回调
onFolderModeDragEnd  // (x, y) → 返回 bucketId | null
onFolderAnimationComplete  // (bucketId) 吸入动画完成
onDragStart          // 拖动开始
onDragUpdate         // (x, y) 拖动更新
onDetail             // 点击查看详情
```

### 3.2 CategoryDropRow（分类桶）

**文件**：`widgets/category_drop_row.dart`

**功能**：
- 从底部滑入显示（300ms slide + fade）
- 桶激活弹性动画（scale 0.82↔1.2, lift 0↔-8dp, width 68↔88dp）
- 碰撞检测（cardCenter vs bucketRect，圆心距离 < 280px 粘附）
- 水平滑动忽略（|offsetX| > 500px 时不激活桶）
- 边缘滚动（靠近列表边缘 100px 范围内自动滚动，speed 6~36）
- 手动点击桶触发选择

**Spring 参数**：
```dart
_scaleSpring: stiffness=320, dampingRatio=0.6   // scale
_otherSpring: stiffness=320, dampingRatio=0.7     // lift, width
```

**碰撞检测**：
```dart
_bandPadding = 90        // 垂直频道区域
_stickyRadius = 280     // 粘附半径
_horizontalSwipeThreshold = 500  // 水平滑动忽略阈值
```

### 3.3 WordDragNotifier（状态管理）

**文件**：`providers/word_drag_notifier.dart`

**职责**：
- 管理 WordDragState（不可变）
- 处理拖动事件（onDragStart/Update）
- 区域检测（mark zone / delete zone 透明度计算）
- 文件夹模式进入/退出
- 桶选择（selectBucket → _moveToNextWord）
- 单词操作（markNew/markReviewed/markMastered/delete/skip）
- 提示显示/隐藏

**ZoneType**：`none / mark / delete`

### 3.4 WordDragState（状态模型）

**文件**：`providers/word_drag_state.dart`

**字段**：
```dart
words                  // 单词列表
currentIndex           // 当前索引
cardOffset             // 卡片偏移 Offset
isDragging             // 是否拖动中
activeZone             // ZoneType
markZoneOpacity / deleteZoneOpacity  // 区域透明度
showMarkSuccessHint / showMarkNewSuccessHint / showMasteredSuccessHint / showDeleteSuccessHint  // 提示
showDetails            // 详情页显示
isFolderMode           // 分类桶模式
activeCategoryBucketId  // 当前激活桶 ID
```

---

## 四、待完善功能

### 4.1 分类数据持久化

**问题**：当前 `selectBucket()` 只调用 `_moveToNextWord()`，没有实际保存分类结果。

**需要实现**：
- 每个 bucket（noun/verb/adj/adv/other）维护自己的单词列表
- 分类后的单词需要持久化到本地（如 SharedPreferences / SQLite）
- 后续复习时能从对应分类加载

**接口扩展**：
```dart
// WordDragNotifier 新增
Map<String, List<Word>> get categorizedWords;
void categorizeWord(String bucketId, Word word);
void loadCategorizedWords();
void saveCategorizedWords();
```

### 4.2 单词详情页完善

**现状**：当前是简单的 overlay（`_buildDetailOverlay`），仅展示文本。

**需要实现**：
- 完整的 `WordDetailPage`（`pages/word_detail_page.dart`）
- 音标发音（集成 TTS）
- 例句朗读
- 笔记功能

### 4.3 遗留代码清理

**文件**：`providers/draggable_word_card_controller.dart`

**问题**：该控制器在旧架构中使用，当前 `DraggableWordCard` 已自行管理状态，不再需要此控制器。

**操作**：删除该文件，更新 `word_drag.dart` 导出。

### 4.4 复习调度系统

**问题**："稍后复习"的单词只是移至列表末尾，没有基于遗忘曲线调度。

**需要实现**（后续扩展）：
- SM-2 或 Anki 间隔重复算法
- 单词下次复习时间记录
- 从"稍后复习"池中按计划取出

### 4.5 音效与触觉反馈

**现状**：仅在滑动确认时有 `HapticFeedback.mediumImpact()`。

**需要实现**：
- 各操作音效（swipe/select/hint）
- 详细的触觉反馈模式

---

## 五、关键常量对照表

| 常量 | 值 | 位置 | 说明 |
|------|-----|------|------|
| `_threshold` | 160 | draggable_word_card.dart | 滑动确认阈值 |
| `_folderModeThreshold` | 300 | draggable_word_card.dart / category_drop_row.dart | 下滑进入文件夹模式 |
| `_flingThreshold` | 800 | draggable_word_card.dart | 快速滑动速度阈值 |
| `_actionIndicatorThreshold` | 100 | draggable_word_card.dart | Action Indicator 阈值 |
| `_actionIndicatorFolderThreshold` | 150 | draggable_word_card.dart | Action Indicator 文件夹模式阈值 |
| `_edgeScrollThreshold` | 100 | category_drop_row.dart | 边缘滚动触发距离 |
| `_minScrollSpeed` | 6 | category_drop_row.dart | 边缘滚动最小速度 |
| `_maxScrollSpeed` | 36 | category_drop_row.dart | 边缘滚动最大速度 |
| `_bandPadding` | 90 | category_drop_row.dart | 垂直频道区域 |
| `_stickyRadius` | 280 | category_drop_row.dart | 粘附半径 |
| `_horizontalSwipeThreshold` | 500 | category_drop_row.dart | 水平滑动忽略阈值 |

---

## 六、交互流程图

```
用户触摸卡片
    ↓
onPanStart → onDragStart → Notifier.isDragging = true
    ↓
拖动中 (onPanUpdate)
    ↓
y > 300? ─否→ 无文件夹模式
    │是
    ↓
显示 CategoryDropRow + 开始碰撞检测
    ↓
在桶上松开?
    ├──否→ _animateSpringBack() → 回弹
    │
    └──是→ _animateSuckIntoFolder() (250ms)
                ↓
          onFolderAnimationComplete(bucketId)
                ↓
          Notifier.selectBucket(bucketId)
                ↓
          _exitFolderMode() + _moveToNextWord()
                ↓
          下一张卡片出现

左滑(x < -160) → _animateSwipeOut → onSwipeLeft → _markAsReviewed()
右滑(x > +160) → _animateSwipeOut → onSwipeRight → _markAsMastered()
上滑(y < -160) → _animateSwipeOut → onSwipeUp → _skipWord() + 显示详情
```

---

## 七、禁止事项

1. **不要在 `DraggableWordCard` 内部调用 `Notifier` 方法** — 手势处理和动画逻辑属于 UI 层，只通过回调与外部通信
2. **不要在动画期间调用 `onDragUpdate`** — `_isAnimating` 标志确保动画期间状态不被外部干扰
3. **不要手动调用 `dispose()` 后继续使用 Controller** — 需加守卫检查
4. **不要在 `CategoryDropRow` 隐藏时更新桶位置** — `visible=false` 时清空 `_bucketRects`
