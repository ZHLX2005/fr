import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../widgets/theme/zen_theme.dart';

/// dBFS → [0,1] 显示比例。-60dB → 0,0dB → 1,线性,带 NaN/越界钳制。
///
/// 顶层函数:painter 和 LevelMeterView 共用,也方便单测。
double dbToRatio(double db) {
  if (db.isNaN || db.isInfinite) return 0.0;
  if (db <= -60.0) return 0.0;
  if (db >= 0.0) return 1.0;
  return (db + 60.0) / 60.0;
}

/// 段数常量单点定义,供 [LevelMeterView] 和 [_MeterStrip] 共用。
const int _kMeterSegments = 16;

/// 实时幅度波形 —— 中央基线上下对称的条形包络。
///
/// 订阅 [dbListenable],内部维护环形缓冲(默认 200 帧 ≈ 200px @ 1px/列)。
/// 仅在录音中(`active=true`)时追加新帧;暂停/停止时保留最后一帧静止。
class WaveformView extends StatefulWidget {
  final ValueListenable<double> dbListenable;
  final bool active;

  /// 缓冲帧数(同时也是最大显示列数,1 帧 = 1 列)。
  final int maxBars;

  const WaveformView({
    super.key,
    required this.dbListenable,
    required this.active,
    this.maxBars = 200,
  });

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<WaveformView> {
  late final ListQueue<double> _dbs;

  @override
  void initState() {
    super.initState();
    _dbs = ListQueue<double>(widget.maxBars);
    widget.dbListenable.addListener(_onDb);
  }

  @override
  void didUpdateWidget(covariant WaveformView old) {
    super.didUpdateWidget(old);
    // false→true 边沿:新一次录音开始,清空上一轮残留帧。
    // 不在 true→false 清空:停止时仍需展示最后一次的波形。
    if (widget.active && !old.active) {
      _dbs.clear();
    }
    if (old.dbListenable != widget.dbListenable) {
      old.dbListenable.removeListener(_onDb);
      widget.dbListenable.addListener(_onDb);
    }
  }

  void _onDb() {
    if (!widget.active) return; // 非录音态不追加,保留静态画面
    final v = widget.dbListenable.value;
    if (_dbs.length >= widget.maxBars) _dbs.removeFirst();
    _dbs.add(v);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.dbListenable.removeListener(_onDb);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: WaveformPainter(
        dbs: _dbs.toList(growable: false),
        baseColor: ZenColors.sage,
        hotColor: ZenColors.mutedRed,
        centerLine: ZenColors.hair,
      ),
      size: const Size.fromHeight(140),
      isComplex: true,
      willChange: true,
    );
  }
}

/// 波形 painter。中央基线 + 上下对称条形。
///
/// 公开(public)以便单测直接构造并验证 [shouldRepaint] 契约。
class WaveformPainter extends CustomPainter {
  final List<double> dbs;
  final Color baseColor;
  final Color hotColor;
  final Color centerLine;

  const WaveformPainter({
    required this.dbs,
    required this.baseColor,
    required this.hotColor,
    required this.centerLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cy = h / 2;
    final maxBarH = cy - 4; // 上下各留 4px

    // 基线
    final linePaint = Paint()
      ..color = centerLine
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, cy), Offset(w, cy), linePaint);

    if (dbs.isEmpty) return;

    final barPaint = Paint()..style = PaintingStyle.fill;
    final step = w / dbs.length;
    for (var i = 0; i < dbs.length; i++) {
      final ratio = dbToRatio(dbs[i]);
      // 0.7 次幂:让小信号也可见,大信号更突出(视觉冲击)
      final mag = math.pow(ratio, 0.7).toDouble() * maxBarH;
      // 过载(>−3dBFS,即 ratio > 0.95)染红警示
      barPaint.color = ratio > 0.95 ? hotColor : baseColor;
      final x = i * step + step / 2;
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, cy), width: step * 0.7, height: mag * 2),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter old) {
    // 引用不同 → 内容可能变了 → 重绘。dbs 是 build 时新建的 toList,所以每次 setState 都会不同。
    return !identical(dbs, old.dbs) ||
        baseColor != old.baseColor ||
        hotColor != old.hotColor ||
        centerLine != old.centerLine;
  }
}

/// 水平电平条:16 段 + 当前 dBFS 数值。
///
/// 单声道只渲染一条;v1 mono 固定。stereo 扩展 hook:后续可加第二 listenable。
class LevelMeterView extends StatelessWidget {
  final ValueListenable<double> dbListenable;
  final bool active;

  const LevelMeterView({
    super.key,
    required this.dbListenable,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: dbListenable,
      builder: (context, _) {
        final ratio = active ? dbToRatio(dbListenable.value) : 0.0;
        final litCount = (ratio * _kMeterSegments).round();
        return Row(
          children: [
            Text('L', style: ZenText.monoDigitSmall),
            const SizedBox(width: 6),
            Expanded(child: _MeterStrip(litCount: litCount)),
            const SizedBox(width: 6),
            Text('R', style: ZenText.monoDigitSmall),
            const SizedBox(width: 12),
            SizedBox(
              width: 64,
              child: Text(
                '${dbListenable.value.toStringAsFixed(1)} dB',
                style: ZenText.monoDigitSmall,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MeterStrip extends StatelessWidget {
  final int litCount;
  const _MeterStrip({required this.litCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_kMeterSegments, (i) {
        final lit = i < litCount;
        // 0-9 sage,10-13 浅黄(用 secondary 代替,zen 无黄),14-15 mutedRed
        final color = i < 10
            ? ZenColors.sage
            : (i < 14 ? ZenColors.secondary : ZenColors.mutedRed);
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            height: 10,
            decoration: BoxDecoration(
              color: lit ? color : ZenColors.hair.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      }),
    );
  }
}
