import '../../../widgets/context_colors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'const_metronome.dart';

/// 节拍可视化指示器组件
///
/// 用 [ValueListenable] 单独订阅 currentBeat，一拍闪一下的时候只有这几个圆点
/// 重建；顶层的 BPM/拍号/播放按钮不会跟着一起 rebuild。
class BeatIndicator extends StatelessWidget {
  const BeatIndicator({
    super.key,
    required this.beatCount,
    required this.currentBeatListenable,
    required this.isPlaying,
    required this.beatPattern,
  });

  final int beatCount;
  final ValueListenable<int> currentBeatListenable;
  final bool isPlaying;
  final BeatPattern beatPattern;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: currentBeatListenable,
      builder: (context, currentBeat, _) {
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: List.generate(beatCount, (index) {
            final accentLevel = beatPattern.getAccentLevel(index);
            final isActive = index == currentBeat && isPlaying;
            return _BeatDot(
              accentLevel: accentLevel,
              isActive: isActive,
              beatIndex: index,
            );
          }),
        );
      },
    );
  }
}

class _BeatDot extends StatefulWidget {
  const _BeatDot({
    required this.accentLevel,
    required this.isActive,
    required this.beatIndex,
  });

  final AccentLevel accentLevel;
  final bool isActive;
  final int beatIndex;

  @override
  State<_BeatDot> createState() => _BeatDotState();
}

class _BeatDotState extends State<_BeatDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(_BeatDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.forward().then((_) => _controller.reverse());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = AccentColor.getColor(context, widget.accentLevel);
    final size = widget.accentLevel == AccentLevel.accent ? 40.0 : 32.0;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isActive ? color : color.withValues(alpha: 0.3),
              boxShadow: widget.isActive
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                '${widget.beatIndex + 1}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: widget.accentLevel == AccentLevel.accent ? 14 : 12,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// BPM 滚轮选择器
class BpmWheelPicker extends StatefulWidget {
  const BpmWheelPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = MetronomeDefaults.minBpm,
    this.max = MetronomeDefaults.maxBpm,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  State<BpmWheelPicker> createState() => _BpmWheelPickerState();
}

class _BpmWheelPickerState extends State<BpmWheelPicker> {
  late FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(
      initialItem: widget.value - widget.min,
    );
  }

  @override
  void didUpdateWidget(BpmWheelPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.animateToItem(
        widget.value - widget.min,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = widget.max - widget.min + 1;

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // 选中指示器
          Center(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.outline, width: 1),
              ),
            ),
          ),
          // 滚轮
          ListWheelScrollView.useDelegate(
            controller: _controller,
            itemExtent: 50,
            perspective: 0.004,
            diameterRatio: 1.5,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (index) {
              widget.onChanged(index + widget.min);
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: itemCount,
              builder: (context, index) {
                final value = index + widget.min;
                final isSelected = value == widget.value;
                return Center(
                  child: AnimatedDefaultTextStyle(
                    duration: Duration(milliseconds: 150),
                    style: TextStyle(
                      fontSize: isSelected ? 32 : 22,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected
                          ? context.colors.accent
                          : context.colors.textMuted,
                    ),
                    child: Text(value.toString()),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 拍号选择器
class TimeSignaturePicker extends StatelessWidget {
  TimeSignaturePicker({
    super.key,
    required this.patterns,
    required this.selectedPattern,
    required this.onPatternSelected,
  });

  final List<BeatPattern> patterns;
  final BeatPattern selectedPattern;
  final ValueChanged<BeatPattern> onPatternSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(25),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 8),
        itemCount: patterns.length,
        separatorBuilder: (_, index) => SizedBox(width: 8),
        itemBuilder: (context, index) {
          final pattern = patterns[index];
          final isSelected = pattern.name == selectedPattern.name;
          return GestureDetector(
            onTap: () => onPatternSelected(pattern),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? context.colors.accent : Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
                borderRadius: BorderRadius.circular(20),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: context.colors.accent.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                pattern.name,
                style: TextStyle(
                  color: isSelected ? Theme.of(context).colorScheme.onSurface : context.colors.text,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 播放控制按钮
class PlayControlButton extends StatefulWidget {
  const PlayControlButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
  });

  final bool isPlaying;
  final VoidCallback onPressed;

  @override
  State<PlayControlButton> createState() => _PlayControlButtonState();
}

class _PlayControlButtonState extends State<PlayControlButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: widget.isPlaying ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(PlayControlButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.accent,
              boxShadow: [
                BoxShadow(
                  color: context.colors.accent.withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              widget.isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
              color: Theme.of(context).colorScheme.onSurface,
              size: 48,
            ),
          );
        },
      ),
    );
  }
}

/// BPM 微调按钮
class BpmAdjustButton extends StatelessWidget {
  BpmAdjustButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 48,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.colors.surface,
          border: Border.all(color: context.colors.outline, width: 1),
        ),
        child: Icon(
          icon,
          color: context.colors.text,
          size: size * 0.5,
        ),
      ),
    );
  }
}

/// Tap Tempo 按钮
class TapTempoButton extends StatelessWidget {
  TapTempoButton({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.colors.outline, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, color: context.colors.text, size: 20),
            SizedBox(width: 8),
            Text(
              'TAP',
              style: TextStyle(
                color: context.colors.text,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 速度标签
class TempoMarking extends StatelessWidget {
  const TempoMarking({super.key, required this.bpm});

  final int bpm;

  String get _marking {
    if (bpm < 40) return 'Grave';
    if (bpm < 60) return 'Largo';
    if (bpm < 66) return 'Larghetto';
    if (bpm < 76) return 'Adagio';
    if (bpm < 108) return 'Andante';
    if (bpm < 120) return 'Moderato';
    if (bpm < 156) return 'Allegro';
    if (bpm < 176) return 'Vivace';
    if (bpm < 200) return 'Presto';
    return 'Prestissimo';
  }

  String get _italian {
    if (bpm < 40) return '庄板';
    if (bpm < 60) return '广板';
    if (bpm < 66) return '小广板';
    if (bpm < 76) return '柔板';
    if (bpm < 108) return '行板';
    if (bpm < 120) return '中板';
    if (bpm < 156) return '快板';
    if (bpm < 176) return '活板';
    if (bpm < 200) return '急板';
    return '最急板';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '$_marking ($_italian)',
      style: TextStyle(
        color: context.colors.textMuted,
        fontSize: 14,
      ),
    );
  }
}
