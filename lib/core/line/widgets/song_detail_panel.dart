import 'package:flutter/material.dart';
import '../models/line_models.dart';
import 'rotating_cover.dart';
import 'song_list_tile.dart';

/// 边框风格
enum GameBorderStyle { none, solid, double_, dashed }

/// 线条密度
enum LineDensity { sparse, normal, dense }

class GameBorderStylePicker extends StatelessWidget {
  final GameBorderStyle selected;
  final ValueChanged<GameBorderStyle> onChanged;
  final Color color;

  const GameBorderStylePicker({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: GameBorderStyle.values.map((style) {
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
              child: Text(
                style == GameBorderStyle.none ? '无' :
                style == GameBorderStyle.solid ? '单' :
                style == GameBorderStyle.double_ ? '双' : '虚',
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected ? color : color.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
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

/// 歌曲详情面板
class SongDetailPanel extends StatelessWidget {
  final SongData song;
  final GameBorderStyle borderStyle;
  final LineDensity lineDensity;
  final ValueChanged<GameBorderStyle> onBorderStyleChanged;
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
            GameBorderStylePicker(
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
