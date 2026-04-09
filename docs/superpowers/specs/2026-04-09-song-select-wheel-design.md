# 选歌页面左侧滚轮重设计

## 背景

当前 `SongSelectPage` 左侧使用 `ListView.builder` + `SongListTile`（含封面、歌名、艺术家、时长），占据 30% 宽度。需要改为极简线条主义风格的歌词滚轮式选歌。

## 设计决策

| 决策项 | 选择 |
|--------|------|
| 歌名排列 | 右对齐 + 左侧短横线指示器 |
| 滚动效果 | 歌词渐变流（三档透明度/字号渐变） |
| 左侧宽度 | 30% 保持不变 |
| 手势交互 | 仅左侧滚轮滑动选歌，右侧去掉滑动切换 |
| 分割线 | 去掉左右面板分割线 |

## 左侧歌曲滚轮

### 布局
- 占屏幕宽度 30%，无分割线、无标题栏、无边框
- 内容垂直水平居中
- 使用 `ListWheelScrollView` + `FixedExtentScrollController` 实现滚轮
- 通过 `ListWheelChildBuilderDelegate` 构建歌名项
- `onSelectedItemChanged` 回调驱动选中状态更新
- 松手后自动吸附到最近歌曲（`ListWheelScrollView` 内置行为）

### 视觉层次（三档渐变）
- **选中项**：主题色、22px、font-weight 200、letter-spacing 4px
- **邻项（上下各一）**：16px、50% 透明度、灰色
- **远项（最外层可见）**：12px、25% 透明度、浅灰
- `ListWheelScrollView` 的 `diameterRatio` 和 `offAxisFraction` 控制透视效果，保持平面化
- `perspective` 设为默认值，避免 3D 畸变

### 短横线指示器
- 固定在滚轮左侧中央，使用 `Stack` 叠加
- 宽度约 24px，高度 2px，圆角 1px
- 从主题色渐变到透明（`LinearGradient` 从左到右：primary → transparent）
- 位置固定不随滚轮滚动

### 歌名项实现
- 每项为纯 `Text` widget，右对齐
- 无封面、无艺术家、无时长、无边框
- 使用 `SizedBox` 或 `Container` 统一每项高度（约 48px），确保 `itemExtent` 一致

## 右侧详情面板

### 变更
- 移除包裹右侧面板的 `GestureDetector` 及其 `onVerticalDragEnd` 滑动切换逻辑
- 移除 `_onSwipeUp()` 和 `_onSwipeDown()` 方法
- 保留所有现有内容：旋转封面、歌名、艺术家、难度星级、时长、简介、边框/密度选择器、START 按钮

### 联动
- 左侧 `onSelectedItemChanged` 触发 `setState(() => _selectedSong = _songs[index])`
- 右侧 `SongDetailPanel` 通过 `didUpdateWidget` 自动响应歌曲切换

## 涉及文件

| 文件 | 变更 |
|------|------|
| `lib/core/line/pages/song_select_page.dart` | 重写左侧面板为滚轮；移除滑动切换手势 |
| `lib/core/line/widgets/song_list_tile.dart` | 不再被选歌页使用（保留给其他可能的用途） |

## 不做的事

- 不修改右侧面板样式
- 不修改主题色系统
- 不删除 `SongListTile`（可能有其他引用）
- 不改变歌曲数据加载逻辑
