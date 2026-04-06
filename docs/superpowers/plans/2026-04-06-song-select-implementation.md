# 选歌界面 + 音乐系统 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 line_demo 添加选歌界面、音乐系统支持，包括歌曲列表/详情/AI乐谱生成脚本

**Architecture:** 采用分层架构 - 数据层（SongData/ChartRepository）、UI层（选歌页面/旋转封面/详情面板）、游戏层（现有line_demo_page）。数据通过 ChartRepository 从 assets 目录加载 JSON 乐谱文件。

**Tech Stack:** Flutter + Dart, Python + librosa（AI脚本）

---

## 文件结构

```
lib/core/line/
├── pages/
│   ├── song_select_page.dart     # 新增：选歌界面主页面
│   └── line_demo_page.dart      # 修改：添加选歌入口
├── models/
│   └── line_models.dart         # 修改：添加 SongData
└── repository/
    └── chart_repository.dart    # 新增：乐谱数据仓库

assets/
├── audio/                       # 歌曲音频（用户添加）
├── covers/                      # 歌曲封面（用户添加）
└── charts/
    ├── song_001.json           # 示例乐谱
    └── songs_index.json        # 歌曲索引

scripts/
└── chart_generator/            # AI 生成脚本（不提交git）
```

---

## Task 1: 数据模型

**Files:**
- Modify: `lib/core/line/models/line_models.dart`

- [ ] **Step 1: 添加 SongData 数据模型**

在 `line_models.dart` 末尾添加：

```dart
/// 歌曲数据
class SongData {
  final String id;
  final String name;
  final String artist;
  final String intro;
  final String audioPath;
  final String coverPath;
  final int bpm;
  final int duration;
  final int difficulty;
  final int dropDuration;
  final List<NoteEvent> notes;

  const SongData({
    required this.id,
    required this.name,
    required this.artist,
    required this.intro,
    required this.audioPath,
    required this.coverPath,
    required this.bpm,
    required this.duration,
    required this.difficulty,
    required this.dropDuration,
    required this.notes,
  });

  factory SongData.fromJson(Map<String, dynamic> json, List<NoteEvent> notes) {
    return SongData(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      artist: json['artist'] as String? ?? 'Unknown',
      intro: json['intro'] as String? ?? '',
      audioPath: json['audioPath'] as String? ?? '',
      coverPath: json['coverPath'] as String? ?? '',
      bpm: json['bpm'] as int? ?? 120,
      duration: json['duration'] as int? ?? 180,
      difficulty: json['difficulty'] as int? ?? 1,
      dropDuration: json['dropDuration'] as int? ?? 2500,
      notes: notes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artist': artist,
      'intro': intro,
      'audioPath': audioPath,
      'coverPath': coverPath,
      'bpm': bpm,
      'duration': duration,
      'difficulty': difficulty,
      'dropDuration': dropDuration,
      'notes': notes.map((n) => {
        'time': n.time,
        'column': n.column,
        'type': n.type.name,
        if (n.direction != null) 'direction': n.direction!.name,
        if (n.holdDuration != null) 'holdDuration': n.holdDuration,
      }).toList(),
    };
  }
}
```

- [ ] **Step 2: 运行 build_runner 生成代码**

Run: `cd D:\DevProjects\my\github\fr && flutter pub run build_runner build --delete-conflicting-outputs`
Expected: 构建成功，无错误

- [ ] **Step 3: 提交**

```bash
git add lib/core/line/models/line_models.dart
git commit -m "feat(line): add SongData model for song management"
```

---

## Task 2: 乐谱数据仓库

**Files:**
- Create: `lib/core/line/repository/chart_repository.dart`

- [ ] **Step 1: 创建 ChartRepository**

```dart
import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/line_models.dart';

/// 乐谱数据仓库
class ChartRepository {
  static const String _chartsPath = 'assets/charts/';
  static const String _indexFile = 'songs_index.json';

  /// 加载歌曲索引
  static Future<List<SongData>> loadAllSongs() async {
    try {
      final indexJson = await rootBundle.loadString('$_chartsPath$_indexFile');
      final indexData = jsonDecode(indexJson) as Map<String, dynamic>;
      final songsList = indexData['songs'] as List? ?? [];
      
      final songs = <SongData>[];
      for (final songInfo in songsList) {
        final songId = songInfo['id'] as String;
        final chartJson = await rootBundle.loadString('$_chartsPath$songId.json');
        final chartData = jsonDecode(chartJson) as Map<String, dynamic>;
        
        final notesRaw = chartData['notes'] as List? ?? [];
        final notes = notesRaw
            .whereType<Map<String, dynamic>>()
            .map((n) => NoteEvent.fromJson(n))
            .toList();
        
        songs.add(SongData.fromJson(chartData, notes));
      }
      return songs;
    } catch (e) {
      debugPrint('Failed to load songs: $e');
      return [];
    }
  }

  /// 根据ID加载单个歌曲
  static Future<SongData?> loadSong(String id) async {
    try {
      final chartJson = await rootBundle.loadString('$_chartsPath$id.json');
      final chartData = jsonDecode(chartJson) as Map<String, dynamic>;
      
      final notesRaw = chartData['notes'] as List? ?? [];
      final notes = notesRaw
          .whereType<Map<String, dynamic>>()
          .map((n) => NoteEvent.fromJson(n))
          .toList();
      
      return SongData.fromJson(chartData, notes);
    } catch (e) {
      debugPrint('Failed to load song $id: $e');
      return null;
    }
  }
}
```

- [ ] **Step 2: 创建 songs_index.json**

```json
{
  "songs": [
    {"id": "test_chart"}
  ]
}
```

- [ ] **Step 3: 提交**

```bash
git add lib/core/line/repository/chart_repository.dart assets/charts/songs_index.json
git commit -m "feat(line): add ChartRepository for loading songs"
```

---

## Task 3: 旋转封面组件

**Files:**
- Create: `lib/core/line/widgets/rotating_cover.dart`

- [ ] **Step 1: 创建 RotatingCover 组件**

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 旋转封面组件（胶片效果）
class RotatingCover extends StatefulWidget {
  final String imagePath;
  final double size;
  final double borderWidth;

  const RotatingCover({
    super.key,
    required this.imagePath,
    this.size = 120,
    this.borderWidth = 2,
  });

  @override
  State<RotatingCover> createState() => _RotatingCoverState();
}

class _RotatingCoverState extends State<RotatingCover>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * math.pi,
          child: child,
        );
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: 0.5),
            width: widget.borderWidth,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.2),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            widget.imagePath,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: color.withValues(alpha: 0.1),
                child: Icon(
                  Icons.music_note,
                  color: color.withValues(alpha: 0.5),
                  size: widget.size * 0.4,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/core/line/widgets/rotating_cover.dart
git commit -m "feat(line): add RotatingCover widget with film effect"
```

---

## Task 4: 歌曲列表项组件

**Files:**
- Create: `lib/core/line/widgets/song_list_tile.dart`

- [ ] **Step 1: 创建 DifficultyStars 组件（在 song_list_tile.dart 中）**

```dart
import 'package:flutter/material.dart';

/// 难度星级显示
class DifficultyStars extends StatelessWidget {
  final int difficulty;
  final double size;

  const DifficultyStars({
    super.key,
    required this.difficulty,
    this.size = 14,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final isFilled = index < difficulty;
        return Icon(
          isFilled ? Icons.star : Icons.star_border,
          color: isFilled ? color : color.withValues(alpha: 0.3),
          size: size,
        );
      }),
    );
  }
}

/// 歌曲列表项
class SongListTile extends StatelessWidget {
  final SongData song;
  final bool isSelected;
  final VoidCallback onTap;

  const SongListTile({
    super.key,
    required this.song,
    required this.isSelected,
    required this.onTap,
  });

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // 旋转封面
            RotatingCover(
              imagePath: song.coverPath,
              size: 50,
              borderWidth: 1,
            ),
            const SizedBox(width: 12),
            // 歌曲信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? color : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _formatDuration(song.duration),
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DifficultyStars(difficulty: song.difficulty, size: 10),
                    ],
                  ),
                ],
              ),
            ),
            // START 按钮（选中时显示）
            if (isSelected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color, width: 1),
                ),
                child: Text(
                  'START',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                    letterSpacing: 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/core/line/widgets/song_list_tile.dart
git commit -m "feat(line): add SongListTile and DifficultyStars widgets"
```

---

## Task 5: 歌曲详情面板

**Files:**
- Create: `lib/core/line/widgets/song_detail_panel.dart`

- [ ] **Step 1: 创建 BorderStylePicker 和 LineDensityPicker**

```dart
import 'package:flutter/material.dart';

/// 边框风格
enum BorderStyle { none, solid, double_, dashed }

/// 线条密度
enum LineDensity { sparse, normal, dense }

class BorderStylePicker extends StatelessWidget {
  final BorderStyle selected;
  final ValueChanged<BorderStyle> onChanged;
  final Color color;

  const BorderStylePicker({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: BorderStyle.values.map((style) {
        final isSelected = style == selected;
        return GestureDetector(
          onTap: () => onChanged(style),
          child: Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? color : color.withValues(alpha: 0.3),
                width: isSelected ? 2 : 1,
              ),
              color: isSelected ? color.withValues(alpha: 0.1) : null,
            ),
            child: Center(
              child: CustomPaint(
                size: const Size(20, 20),
                painter: _BorderStyleIconPainter(style: style, color: color),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _BorderStyleIconPainter extends CustomPainter {
  final BorderStyle style;
  final Color color;

  _BorderStyleIconPainter({required this.style, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);

    switch (style) {
      case BorderStyle.none:
        // 空
        break;
      case BorderStyle.solid:
        canvas.drawRect(rect, paint);
        break;
      case BorderStyle.double_:
        canvas.drawRect(rect, paint);
        canvas.drawRect(rect.deflate(3), paint);
        break;
      case BorderStyle.dashed:
        final path = Path()..addRect(rect);
        canvas.drawPath(
          path,
          paint..strokeWidth = 1..style = PaintingStyle.stroke,
        );
        // 简化：用点表示虚线
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LineDensityPicker extends StatelessWidget {
  final LineDensity selected;
  final ValueChanged<LineDensity> onChanged;
  final Color color;

  const LineDensityPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: LineDensity.values.map((density) {
        final isSelected = density == selected;
        final label = switch (density) {
          LineDensity.sparse => '疏',
          LineDensity.normal => '中',
          LineDensity.dense => '密',
        };
        return GestureDetector(
          onTap: () => onChanged(density),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? color : color.withValues(alpha: 0.3),
                width: isSelected ? 2 : 1,
              ),
              color: isSelected ? color.withValues(alpha: 0.1) : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? color : color.withValues(alpha: 0.6),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
```

- [ ] **Step 2: 创建 SongDetailPanel**

```dart
import 'rotating_cover.dart';
import 'song_list_tile.dart';

/// 歌曲详情面板
class SongDetailPanel extends StatelessWidget {
  final SongData song;
  final BorderStyle borderStyle;
  final LineDensity lineDensity;
  final ValueChanged<BorderStyle> onBorderStyleChanged;
  final ValueChanged<LineDensity> onLineDensityChanged;
  final VoidCallback onStart;

  const SongDetailPanel({
    super.key,
    required this.song,
    required this.borderStyle,
    required this.lineDensity,
    required this.onBorderStyleChanged,
    required this.onLineDensityChanged,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;

    return Column(
      children: [
        const SizedBox(height: 32),
        // 大尺寸旋转封面
        RotatingCover(
          imagePath: song.coverPath,
          size: 180,
          borderWidth: 3,
        ),
        const SizedBox(height: 24),
        // 歌曲名
        Text(
          song.name,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w200,
            color: color,
            letterSpacing: 2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        // 艺术家
        Text(
          song.artist,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w300,
            color: theme.textTheme.bodyMedium?.color,
          ),
        ),
        const SizedBox(height: 16),
        // 难度 + 时长
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DifficultyStars(difficulty: song.difficulty, size: 18),
            const SizedBox(width: 16),
            Text(
              '${song.duration ~/ 60}:${(song.duration % 60).toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 14,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // 简介
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            song.intro,
            style: TextStyle(
              fontSize: 13,
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 28),
        // 边框风格
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '边框',
              style: TextStyle(
                fontSize: 13,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(width: 12),
            BorderStylePicker(
              selected: borderStyle,
              onChanged: onBorderStyleChanged,
              color: color,
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 线条密度
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '线条',
              style: TextStyle(
                fontSize: 13,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(width: 12),
            LineDensityPicker(
              selected: lineDensity,
              onChanged: onLineDensityChanged,
              color: color,
            ),
          ],
        ),
        const Spacer(),
        // START 按钮
        GestureDetector(
          onTap: onStart,
          child: Container(
            width: 200,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: Text(
                'START',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                  letterSpacing: 4,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 48),
      ],
    );
  }
}
```

- [ ] **Step 3: 提交**

```bash
git add lib/core/line/widgets/song_detail_panel.dart
git commit -m "feat(line): add SongDetailPanel with border and density pickers"
```

---

## Task 6: 选歌界面主页面

**Files:**
- Create: `lib/core/line/pages/song_select_page.dart`

- [ ] **Step 1: 创建 SongSelectPage**

```dart
import 'package:flutter/material.dart';
import '../models/line_models.dart';
import '../repository/chart_repository.dart';
import '../widgets/rotating_cover.dart';
import '../widgets/song_list_tile.dart';
import '../widgets/song_detail_panel.dart';
import 'line_demo_page.dart';

/// 选歌界面
class SongSelectPage extends StatefulWidget {
  const SongSelectPage({super.key});

  @override
  State<SongSelectPage> createState() => _SongSelectPageState();
}

class _SongSelectPageState extends State<SongSelectPage> {
  List<SongData> _songs = [];
  SongData? _selectedSong;
  BorderStyle _borderStyle = BorderStyle.solid;
  LineDensity _lineDensity = LineDensity.normal;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    final songs = await ChartRepository.loadAllSongs();
    if (mounted) {
      setState(() {
        _songs = songs;
        _selectedSong = songs.isNotEmpty ? songs.first : null;
        _isLoading = false;
      });
    }
  }

  void _onSongSelected(SongData song) {
    setState(() => _selectedSong = song);
  }

  void _onStart() {
    if (_selectedSong == null) return;
    
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => LineDemoPage(songData: _selectedSong),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Center(
          child: CircularProgressIndicator(color: color),
        ),
      );
    }

    if (_songs.isEmpty) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.music_off, size: 64, color: color.withValues(alpha: 0.3)),
              const SizedBox(height: 16),
              Text(
                'No songs found',
                style: TextStyle(color: color.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Row(
        children: [
          // 左侧歌曲列表 (30%)
          Container(
            width: MediaQuery.of(context).size.width * 0.3,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: color.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                // 标题
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'SONGS',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color.withValues(alpha: 0.6),
                      letterSpacing: 4,
                    ),
                  ),
                ),
                Divider(color: color.withValues(alpha: 0.1), height: 1),
                // 列表
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _songs.length,
                    itemBuilder: (context, index) {
                      final song = _songs[index];
                      return SongListTile(
                        song: song,
                        isSelected: song.id == _selectedSong?.id,
                        onTap: () => _onSongSelected(song),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // 右侧详情面板 (70%)
          Expanded(
            child: _selectedSong != null
                ? SongDetailPanel(
                    song: _selectedSong!,
                    borderStyle: _borderStyle,
                    lineDensity: _lineDensity,
                    onBorderStyleChanged: (style) {
                      setState(() => _borderStyle = style);
                    },
                    onLineDensityChanged: (density) {
                      setState(() => _lineDensity = density);
                    },
                    onStart: _onStart,
                  )
                : const SizedBox(),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 修改 LineDemoPage 接收 songData 参数**

在 `line_models.dart` 的 `ChartData` 中添加 factory 来自 SongData，或者直接在 LineDemoPage 中：

修改 `lib/core/line/pages/line_demo_page.dart` 第 29 行附近，将 `_LineDemoPage` 改为接收 `ChartData`：

```dart
class _LineDemoPage extends StatefulWidget {
  final ChartData chart;
  
  const _LineDemoPage({required this.chart});

  @override
  State<_LineDemoPage> createState() => _LineDemoPageState();
}
```

在 `_LineDemoPageState` 中，将 `_chart` 改为从构造参数获取：

```dart
late ChartData _chart;

@override
void initState() {
  super.initState();
  _chart = widget.chart;
  // ... 其余代码不变
}
```

修改 `LineDemoPage` 的 build 方法接收 songData 参数并转换：

```dart
class LineDemoPage extends StatelessWidget {
  final SongData? songData;
  
  const LineDemoPage({super.key, this.songData});

  @override
  Widget build(BuildContext context) {
    if (songData != null) {
      return _LineDemoPage(chart: ChartData(
        name: songData!.name,
        bpm: songData!.bpm,
        dropDuration: songData!.dropDuration,
        notes: songData!.notes,
      ));
    }
    // 原有加载逻辑...
  }
}
```

- [ ] **Step 3: 修改 line.dart 导出**

修改 `lib/core/line/line.dart` 导出新的页面和组件：

```dart
export 'pages/song_select_page.dart';
export 'pages/line_demo_page.dart';
export 'models/line_models.dart';
export 'widgets/rotating_cover.dart';
export 'widgets/song_list_tile.dart';
export 'widgets/song_detail_panel.dart';
```

- [ ] **Step 4: 提交**

```bash
git add lib/core/line/pages/song_select_page.dart lib/core/line/pages/line_demo_page.dart lib/core/line/line.dart
git commit -m "feat(line): add SongSelectPage with song list and detail panel"
```

---

## Task 7: 串联选歌流程

**Files:**
- Modify: `lib/lab/demos/line_demo.dart`

- [ ] **Step 1: 修改 LineDemo 跳转到选歌页面**

```dart
import '../../core/line/line.dart';

class LineDemo extends DemoPage {
  @override
  String get title => '线';

  @override
  String get description => '线';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const SongSelectPage();  // 改为跳achi选歌页面
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/lab/demos/line_demo.dart
git commit -m "feat(line): route LineDemo to SongSelectPage"
```

---

## Task 8: AI 生成乐谱脚本

**Files:**
- Create: `scripts/chart_generator/generate_chart.py`
- Create: `scripts/chart_generator/requirements.txt`
- Create: `scripts/chart_generator/README.md`
- Modify: `.gitignore`（添加 `scripts/` 排除）

- [ ] **Step 1: 创建 generate_chart.py**

```python
#!/usr/bin/env python3
"""
音乐乐谱生成脚本
使用 librosa 分析音频，生成下落式音游的乐谱 JSON
"""

import argparse
import json
import sys
from pathlib import Path

try:
    import librosa
    import numpy as np
except ImportError:
    print("Error: librosa not installed. Run: pip install -r requirements.txt")
    sys.exit(1)


def detect_bpm(audio_path):
    """检测音频BPM"""
    y, sr = librosa.load(audio_path)
    tempo, _ = librosa.beat.beat_track(y=y, sr=sr)
    return float(tempo)


def detect_beats(audio_path, bpm):
    """检测节拍时间点（ms）"""
    y, sr = librosa.load(audio_path)
    
    # 使用基音跟踪获取更强的节拍检测
    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    beats = librosa.beat.beat_track(
        onset_envelope=onset_env,
        sr=sr,
        bpm=bpm,
        tightness=100,
    )[1]
    
    # 转换为毫秒
    beat_times = librosa.frames_to_time(beats, sr=sr)
    return [int(t * 1000) for t in beat_times]


def generate_notes(beat_times, bpm, column_count=3):
    """根据节拍生成音符"""
    notes = []
    beat_interval_ms = 60000 / bpm  # ms per beat
    
    hold_threshold = beat_interval_ms * 1.5  # 超过1.5拍认为是hold
    consecutive_holds = 0
    
    for i, beat_time in enumerate(beat_times):
        if i < 2:  # 跳过前两个节拍（可能不稳定）
            continue
        
        column = i % column_count
        
        # 判断是否为hold音符
        if i > 0:
            prev_beat = beat_times[i - 1]
            interval = beat_time - prev_beat
            
            if interval > hold_threshold and consecutive_holds == 0:
                # 开始一个hold
                hold_duration = min(int(interval), 1500)  # 最多1.5秒
                notes.append({
                    "time": beat_time,
                    "column": column,
                    "type": "hold",
                    "holdDuration": hold_duration,
                })
                consecutive_holds = 1
                continue
        
        consecutive_holds = 0
        
        # 随机决定是否添加slide（10%概率）
        if i % 4 == 0 and i > 0:
            import random
            if random.random() < 0.1:
                directions = ["up", "down", "left", "right"]
                notes.append({
                    "time": beat_time,
                    "column": column,
                    "type": "slide",
                    "direction": directions[random.randint(0, 3)],
                })
                continue
        
        # 普通tap
        notes.append({
            "time": beat_time,
            "column": column,
            "type": "tap",
        })
    
    return notes


def generate_chart(audio_path, output_path, song_name=None, artist=None, intro=""):
    """生成完整乐谱"""
    print(f"Analyzing: {audio_path}")
    
    # 检测BPM
    bpm = detect_bpm(audio_path)
    print(f"BPM detected: {bpm}")
    
    # 检测节拍
    beat_times = detect_beats(audio_path, bpm)
    print(f"Beats detected: {len(beat_times)}")
    
    # 生成音符
    notes = generate_notes(beat_times, bpm)
    print(f"Notes generated: {len(notes)}")
    
    # 构建乐谱
    chart = {
        "id": Path(audio_path).stem,
        "name": song_name or Path(audio_path).stem,
        "artist": artist or "Unknown",
        "intro": intro,
        "audioPath": f"assets/audio/{Path(audio_path).name}",
        "coverPath": f"assets/covers/{Path(audio_path).stem}.png",
        "bpm": int(bpm),
        "duration": 180,  # 需要从音频元数据获取
        "difficulty": 3,
        "dropDuration": 2500,
        "notes": notes,
    }
    
    # 写入文件
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(chart, f, indent=2, ensure_ascii=False)
    
    print(f"Chart saved to: {output_path}")
    
    # 统计
    tap_count = sum(1 for n in notes if n["type"] == "tap")
    hold_count = sum(1 for n in notes if n["type"] == "hold")
    slide_count = sum(1 for n in notes if n["type"] == "slide")
    print(f"  Tap: {tap_count}, Hold: {hold_count}, Slide: {slide_count}")


def main():
    parser = argparse.ArgumentParser(description="生成音游乐谱")
    parser.add_argument("audio", help="音频文件路径 (m4a, mp3, wav)")
    parser.add_argument("-o", "--output", help="输出JSON路径")
    parser.add_argument("--name", help="歌曲名称")
    parser.add_argument("--artist", help="艺术家名称")
    parser.add_argument("--intro", default="", help="简介")
    
    args = parser.parse_args()
    
    audio_path = Path(args.audio)
    if not audio_path.exists():
        print(f"Error: File not found: {audio_path}")
        sys.exit(1)
    
    output_path = args.output or f"assets/charts/{audio_path.stem}.json"
    
    generate_chart(
        str(audio_path),
        output_path,
        song_name=args.name,
        artist=args.artist,
        intro=args.intro,
    )


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: 创建 requirements.txt**

```
librosa>=0.10.0
numpy>=1.24.0
soundfile>=0.12.0
```

- [ ] **Step 3: 创建 README.md**

```markdown
# 乐谱生成脚本

## 安装

```bash
pip install -r requirements.txt
```

需要安装 ffmpeg 并添加到 PATH。

## 使用方法

```bash
# 基本用法
python generate_chart.py audio.m4a

# 指定输出和元数据
python generate_chart.py audio.m4a -o song.json --name "My Song" --artist "Artist Name" --intro "这是一首..."
```

## 输出

生成 `assets/charts/[song_name].json` 文件，包含完整的乐谱数据。

## 注意事项

- 此脚本仅供本地使用，不加入 git 提交
- 生成的乐谱需要人工校准节奏和判定
- Hold 音符duration可能需要根据实际音乐调整
```

- [ ] **Step 4: 添加到 .gitignore**

```bash
echo "scripts/" >> .gitignore
```

- [ ] **Step 5: 提交**

```bash
git add scripts/chart_generator/generate_chart.py scripts/chart_generator/requirements.txt scripts/chart_generator/README.md .gitignore
git commit -m "feat: add AI chart generator script (local only)"
```

---

## 实施顺序

1. Task 1: 数据模型
2. Task 2: 乐谱数据仓库
3. Task 3: 旋转封面组件
4. Task 4: 歌曲列表项组件
5. Task 5: 歌曲详情面板
6. Task 6: 选歌界面主页面
7. Task 7: 串联选歌流程
8. Task 8: AI 生成乐谱脚本

---

## 验证清单

- [ ] 选歌界面可以显示歌曲列表
- [ ] 点击歌曲可以选中并显示详情
- [ ] 旋转封面持续旋转
- [ ] START 按钮可以跳转到游戏
- [ ] 游戏使用选中的歌曲乐谱
- [ ] AI 脚本可以分析 m4a 并生成 json
