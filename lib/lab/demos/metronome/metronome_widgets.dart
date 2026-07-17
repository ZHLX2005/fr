import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'const_metronome.dart';

/// 节拍可视化指示器组件
class BeatIndicator extends StatelessWidget {
  const BeatIndicator({
    super.key,
    required this.beatCount,
    required this.currentBeat,
    required this.isPlaying,
    required this.beatPattern,
  });

  final int beatCount;
  final int currentBeat;
  final bool isPlaying;
  final BeatPattern beatPattern;

  @override
  Widget build(BuildContext context) {
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
    final color = AccentColor.getColor(widget.accentLevel);
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
                  color: Colors.white,
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
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // 选中指示器
          Center(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
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
                    duration: const Duration(milliseconds: 150),
                    style: TextStyle(
                      fontSize: isSelected ? 32 : 22,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.grey[400],
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
  const TimeSignaturePicker({
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
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(25),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: patterns.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final pattern = patterns[index];
          final isSelected = pattern.name == selectedPattern.name;
          return GestureDetector(
            onTap: () => onPatternSelected(pattern),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).primaryColor : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                pattern.name,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[700],
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
              color: Theme.of(context).primaryColor,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              widget.isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
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
  const BpmAdjustButton({
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
          color: Colors.grey[200],
        ),
        child: Icon(
          icon,
          color: Colors.grey[700],
          size: size * 0.5,
        ),
      ),
    );
  }
}

/// Tap Tempo 按钮
class TapTempoButton extends StatelessWidget {
  const TapTempoButton({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, color: Colors.grey[700], size: 20),
            const SizedBox(width: 8),
            Text(
              'TAP',
              style: TextStyle(
                color: Colors.grey[700],
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

/// 节拍摆锤动画
class PendulumAnimation extends StatefulWidget {
  const PendulumAnimation({
    super.key,
    required this.bpm,
    required this.isPlaying,
  });

  final int bpm;
  final bool isPlaying;

  @override
  State<PendulumAnimation> createState() => _PendulumAnimationState();
}

class _PendulumAnimationState extends State<PendulumAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _updateAnimation();
  }

  @override
  void didUpdateWidget(PendulumAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bpm != oldWidget.bpm || widget.isPlaying != oldWidget.isPlaying) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    if (!widget.isPlaying) {
      _controller.stop();
      return;
    }

    // 计算摆动周期（秒）
    final period = 60.0 / widget.bpm;
    _controller.duration = Duration(milliseconds: (period * 1000).round());

    // 使用正弦曲线实现左右摆动
    _animation = Tween<double>(begin: -0.5, end: 0.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final angle = _animation.value * math.pi / 6; // 最大摆动角度 30 度
          return CustomPaint(
            size: const Size(double.infinity, 150),
            painter: _PendulumPainter(angle: widget.isPlaying ? angle : 0),
          );
        },
      ),
    );
  }
}

class _PendulumPainter extends CustomPainter {
  _PendulumPainter({required this.angle});

  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 0);
    final length = size.height * 0.9;

    final paint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // 绘制摆杆
    final endX = center.dx + math.sin(angle) * length;
    final endY = center.dy + math.cos(angle) * length;
    canvas.drawLine(center, Offset(endX, endY), paint);

    // 绘制摆锤
    final bobPaint = Paint()
      ..color = Colors.grey[700]!
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(endX, endY), 12, bobPaint);

    // 绘制支点
    final pivotPaint = Paint()
      ..color = Colors.grey[500]!
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 6, pivotPaint);
  }

  @override
  bool shouldRepaint(_PendulumPainter oldDelegate) {
    return angle != oldDelegate.angle;
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
        color: Colors.grey[600],
        fontSize: 14,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
