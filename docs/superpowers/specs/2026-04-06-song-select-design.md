# 选歌界面 + 音乐系统 设计文档

## 概述

为 line_demo 添加完整的音乐 + 乐谱系统，包含选歌界面、AI乐谱生成脚本。

## 整体流程

```
点击 Demo → 开场动画（水波+321） → 选歌界面 → 点击START → 开场动画（水波+321） → 游戏
```

## 数据结构

### SongData（歌曲数据）

```dart
class SongData {
  final String id;
  final String name;
  final String artist;
  final String intro;
  final String audioPath;     // 本地音频路径
  final String coverPath;     // 本地封面路径
  final int bpm;
  final int duration;         // 秒
  final int difficulty;       // 1-5 星级
  final int dropDuration;
  final List<NoteEvent> notes;
}
```

### JSON 文件结构（`assets/charts/*.json`）

```json
{
  "id": "song_001",
  "name": "Song Name",
  "artist": "Artist Name",
  "intro": "这是一首...的歌曲",
  "audioPath": "assets/audio/song.mp3",
  "coverPath": "assets/covers/song.png",
  "bpm": 120,
  "duration": 180,
  "difficulty": 3,
  "dropDuration": 2500,
  "notes": [
    {"time": 3000, "column": 1, "type": "tap"},
    {"time": 4000, "column": 0, "type": "hold", "holdDuration": 800}
  ]
}
```

## 选歌界面

### 布局

- **左侧（30%）**：歌曲列表
  - 垂直滚动列表
  - 每项：圆形旋转封面 + 歌曲名 + 艺术家 + 时长 + 难度星级
  - 选中态：边框高亮

- **右侧（70%）**：歌曲详情
  - 大尺寸圆形旋转封面（胶片效果）
  - 歌曲名（标题字体）
  - 艺术家名
  - 简介文字
  - 难度星级 + 时长
  - 边框风格选择：默认/加粗/双线/虚线
  - 线条密度选择：稀疏/标准/密集
  - 主题色：贴合系统主题色
  - 【START】按钮

### 封面胶片效果

- 圆形裁剪
- 持续旋转动画（8秒/圈）
- 边框：细线条圆形边框

## 开场动画

- 保持现有水波入场动画（`WaterExitPainter`）
- 321 倒计时数字显示
- 与现有游戏流程完全一致

## AI 生成乐谱脚本

### 技术栈

- Python 3
- librosa（音频分析/BPM检测/节拍提取）
- ffmpeg（音频格式转换）

### 脚本位置

```
scripts/chart_generator/
├── generate_chart.py    # 主脚本
├── requirements.txt     # 依赖
└── README.md           # 使用说明
```

### 核心功能

1. **BPM检测**：使用 librosa 分析音频，计算平均BPM
2. **节拍检测**：检测音频中的节拍时间点
3. **音符生成**：根据节拍生成 tap 音符
4. **Hold音符**：根据节拍间隔生成（如：连续两个节拍间隔>800ms则生成hold）
5. **Slide音符**：随机分配少量滑动音符

### 输出

- 生成 `assets/charts/[song_name].json`
- 同时输出音符统计：BPM、总音符数、hold数、slide数

### 注意事项

- **不加入git提交**（在 `.gitignore` 中添加 `scripts/chart_generator/`）
- 仅本地开发使用

## 组件列表

| 组件 | 用途 |
|------|------|
| `SongSelectPage` | 选歌界面主页面 |
| `SongListTile` | 左侧歌曲列表项 |
| `SongDetailPanel` | 右侧详情面板 |
| `RotatingCover` | 旋转封面组件（胶片效果） |
| `BorderStylePicker` | 边框风格选择器 |
| `LineDensityPicker` | 线条密度选择器 |
| `DifficultyStars` | 难度星级显示 |
| `SongData` | 歌曲数据模型 |
| `ChartRepository` | 乐谱数据仓库 |

## 文件结构

```
lib/
├── core/line/
│   ├── pages/
│   │   ├── song_select_page.dart    # 新增
│   │   └── line_demo_page.dart       # 修改：添加选歌入口
│   └── models/
│       └── line_models.dart          # 修改：添加 SongData
assets/
├── audio/                            # 歌曲音频
├── covers/                           # 歌曲封面
└── charts/                           # 乐谱 JSON
scripts/
└── chart_generator/                  # AI 生成脚本（不提交git）
```

## 实现顺序

1. 数据模型 + 乐谱加载
2. 选歌界面 UI 框架
3. 旋转封面组件
4. 歌曲列表 + 详情联动
5. 选歌 → 游戏流程串联
6. AI 生成脚本（本地使用）
