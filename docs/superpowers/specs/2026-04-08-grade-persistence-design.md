# 等级持久化与选歌界面展示

## 背景

当前选歌界面的详情面板已有最高分展示（奖杯图标 + 分数），但缺少等级信息。玩家完成一首歌后看到的 S/A/B 等级在返回选歌界面后无法回溯。

## 目标

持久化每首歌的最佳准确率，在选歌界面右侧详情面板的"线条"选择器下方、START 按钮上方，显示对应的等级字母和准确率。

## 数据流

```
游戏结束 → _gameOver()
         → 构建 GameResult（已有）
         → 如果 isNewRecord：保存 accuracy 到 SharedPreferences
         → key: line_high_accuracy_${chart.name.hashCode}

选歌界面 → SongDetailPanel
        → _loadHighScore() 同时加载 _highAccuracy
        → 根据 accuracy 阈值计算 grade letter
        → 在线条选择器下方显示
```

## 持久化方案

- Key: `line_high_accuracy_${chart.name.hashCode}`
- Value: `double`（准确率 0~100，如 `95.2`）
- 更新条件：仅当新分数超过历史最高分时更新（与 `_highScore` 同步）

### 等级计算（复用 GameResult 逻辑）

```dart
String _calculateGrade(double accuracy) {
  if (accuracy >= 100) return 'P';
  if (accuracy >= 95) return 'S';
  if (accuracy >= 85) return 'A';
  if (accuracy >= 70) return 'B';
  if (accuracy >= 50) return 'C';
  return 'D';
}
```

等级颜色与 GameResultPage 一致（经典游戏配色）。

## 显示位置

在线条密度选择器下方、START 按钮上方：

```
[线条] 疏 中 密

      S 95.2%       ← 仅当有记录时显示
     ──────         ← 分隔线

    [ START ]
```

- 等级字母：40px，weight 100，对应等级颜色
- 准确率：13px，weight 300，透明度 0.4
- 仅当 `_highAccuracy > 0` 时显示
- 整体使用 `Spacer()` 上方的固定区域

## 改动文件

| 文件 | 改动 |
|------|------|
| `lib/core/line/pages/line_demo_page.dart` | `_gameOver()` 中：当 `isNewRecord` 时保存 `result.accuracy` |
| `lib/core/line/widgets/song_detail_panel.dart` | 加载 `_highAccuracy`；添加 `_calculateGrade()`；在线条下方显示等级+准确率 |

## 不在范围内

- 等级历史列表
- 准确率趋势图
- 等级解锁/成就系统
