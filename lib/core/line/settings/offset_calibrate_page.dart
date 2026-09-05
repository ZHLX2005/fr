import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/constants.dart';

/// 输入偏移校准：按 BPM 节拍点按几次，取平均误差写入 [lineInputOffsetKey]。
class OffsetCalibratePage extends StatefulWidget {
  final Color primaryColor;
  final int bpm;

  const OffsetCalibratePage({
    super.key,
    required this.primaryColor,
    this.bpm = 120,
  });

  @override
  State<OffsetCalibratePage> createState() => _OffsetCalibratePageState();
}

class _OffsetCalibratePageState extends State<OffsetCalibratePage> {
  static const int _needSamples = 8;

  final Stopwatch _sw = Stopwatch();
  Timer? _beatTimer;
  int _beatIndex = 0;
  final List<int> _errors = [];
  bool _running = false;
  int? _suggested;

  int get _intervalMs => (60000 / widget.bpm).round();

  @override
  void dispose() {
    _beatTimer?.cancel();
    super.dispose();
  }

  void _start() {
    _beatTimer?.cancel();
    _errors.clear();
    _beatIndex = 0;
    _suggested = null;
    _sw
      ..reset()
      ..start();
    setState(() => _running = true);
    // 首拍延迟一个 interval，给用户准备
    _beatTimer = Timer.periodic(Duration(milliseconds: _intervalMs), (_) {
      _onBeat();
    });
  }

  void _onBeat() {
    _beatIndex++;
    HapticFeedback.selectionClick();
    SystemSound.play(SystemSoundType.click);
    if (mounted) setState(() {});
  }

  void _onTap() {
    if (!_running) return;
    final now = _sw.elapsedMilliseconds;
    // 期望拍点：最近的 beat 时刻（从 interval 起算）
    final expected = _beatIndex * _intervalMs;
    // 若尚未响第一拍，忽略
    if (_beatIndex < 1) return;
    final err = now - expected;
    // 只收合理窗口内的样本（±200ms）
    if (err.abs() > 200) return;
    _errors.add(err);
    HapticFeedback.mediumImpact();
    if (_errors.length >= _needSamples) {
      _finish();
    } else {
      setState(() {});
    }
  }

  void _finish() {
    _beatTimer?.cancel();
    _sw.stop();
    final avg = (_errors.reduce((a, b) => a + b) / _errors.length).round();
    // 玩家偏晚 → 正 offset（判定时刻后移）
    setState(() {
      _running = false;
      _suggested = avg.clamp(-150, 150);
    });
  }

  Future<void> _apply() async {
    final v = _suggested;
    if (v == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(lineInputOffsetKey, v);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已应用偏移 ${v >= 0 ? '+' : ''}$v ms')),
      );
      Navigator.of(context).pop(v);
    }
  }

  void _stop() {
    _beatTimer?.cancel();
    _sw.stop();
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.primaryColor;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('偏移校准'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: color,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '跟随节拍点按屏幕中央。完成 $_needSamples 次后给出建议偏移。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'BPM ${widget.bpm} · 间隔 $_intervalMs ms',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _running ? _onTap : null,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color.withValues(alpha: _running ? 0.6 : 0.25),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _suggested != null
                            ? '${_suggested! >= 0 ? '+' : ''}$_suggested ms'
                            : (_running
                                ? '${_errors.length}/$_needSamples'
                                : 'READY'),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w200,
                          color: color.withValues(alpha: 0.7),
                          letterSpacing: 2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (_suggested == null) ...[
                FilledButton(
                  onPressed: _running ? _stop : _start,
                  style: FilledButton.styleFrom(backgroundColor: color),
                  child: Text(_running ? '停止' : '开始校准'),
                ),
              ] else ...[
                FilledButton(
                  onPressed: _apply,
                  style: FilledButton.styleFrom(backgroundColor: color),
                  child: const Text('应用此偏移'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    setState(() => _suggested = null);
                    _start();
                  },
                  child: Text('重试', style: TextStyle(color: color)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
