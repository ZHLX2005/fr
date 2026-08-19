import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_container.dart';

/// 反应力测试 Demo：等待背景变绿后立即点击，测量反应速度（毫秒）。
class ReactionTestDemo extends DemoPage {
  @override
  String get title => '反应力测试';

  @override
  String get slug => 'reaction-test';

  @override
  String get description => '等待颜色变绿立即点击，测量反应速度';

  @override
  Widget buildPage(BuildContext context) => const ReactionTestPage();
}

/// 测试阶段枚举。
enum _Phase {
  idle, // 初始：等待用户开始
  waiting, // 红色：等待变绿，此时点击算抢跳
  ready, // 绿色：立即点击
  tooEarly, // 抢跳：红灯期间点击
  result, // 显示本轮成绩
}

/// 各阶段配色（背景色 + 主文案）统一管理，降低维护成本。
class _PhaseStyle {
  const _PhaseStyle(this.bg, this.accent, this.title, this.hint);

  final Color bg;
  final Color accent;
  final String title;
  final String hint;
}

/// 走主题策略通道：背景/强调色全部从 ColorScheme 派生。
///   waiting 红=别点 → scheme.error；ready 绿=点击 → scheme.primary；
///   tooEarly 橙 → scheme.tertiary；idle/result 深底 → scheme.onSurface。
Map<_Phase, _PhaseStyle> _kPhaseStyles(BuildContext context) {
  final c = Theme.of(context).colorScheme;
  return {
    _Phase.idle: _PhaseStyle(
      c.onSurface,
      c.tertiary,
      '反应力测试',
      '点击屏幕开始',
    ),
    _Phase.waiting: _PhaseStyle(
      c.error,
      c.onSurface,
      '等待绿色…',
      '不要着急，变绿再点',
    ),
    _Phase.ready: _PhaseStyle(
      c.primary,
      c.onSurface,
      '点击！',
      '越快越好',
    ),
    _Phase.tooEarly: _PhaseStyle(
      c.tertiary,
      c.onSurface,
      '太早了！',
      '还没变绿，点击重试',
    ),
    _Phase.result: _PhaseStyle(
      c.onSurface,
      c.tertiary,
      '成绩',
      '点击再来一次',
    ),
  };
}

class ReactionTestPage extends StatefulWidget {
  const ReactionTestPage({super.key});

  @override
  State<ReactionTestPage> createState() => _ReactionTestPageState();
}

class _ReactionTestPageState extends State<ReactionTestPage> {
  final math.Random _rng = math.Random();

  _Phase _phase = _Phase.idle;
  Timer? _greenTimer;
  Stopwatch? _stopwatch;

  int? _lastMs;
  final List<int> _history = [];

  @override
  void dispose() {
    _greenTimer?.cancel();
    super.dispose();
  }

  int? get _bestMs => _history.isEmpty ? null : _history.reduce(math.min);

  int? get _avgMs => _history.isEmpty
      ? null
      : (_history.reduce((a, b) => a + b) / _history.length).round();

  void _handleTap() {
    switch (_phase) {
      case _Phase.idle:
      case _Phase.result:
      case _Phase.tooEarly:
        _startWaiting();
        break;
      case _Phase.waiting:
        // 抢跳：绿灯前点击。
        _greenTimer?.cancel();
        setState(() => _phase = _Phase.tooEarly);
        break;
      case _Phase.ready:
        _recordResult();
        break;
    }
  }

  void _startWaiting() {
    _greenTimer?.cancel();
    setState(() => _phase = _Phase.waiting);
    // 1.2s ~ 4.2s 随机延迟后变绿。
    final delayMs = 1200 + _rng.nextInt(3000);
    _greenTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      _stopwatch = Stopwatch()..start();
      setState(() => _phase = _Phase.ready);
    });
  }

  void _recordResult() {
    final ms = _stopwatch?.elapsedMilliseconds ?? 0;
    _stopwatch?.stop();
    setState(() {
      _lastMs = ms;
      _history.add(ms);
      _phase = _Phase.result;
    });
  }

  void _reset() {
    _greenTimer?.cancel();
    _stopwatch?.stop();
    setState(() {
      _phase = _Phase.idle;
      _lastMs = null;
      _history.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = _kPhaseStyles(context)[_phase]!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('反应力测试'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              tooltip: '重置记录',
              icon: Icon(Icons.refresh),
              onPressed: _reset,
            ),
        ],
      ),
      body: GestureDetector(
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          color: style.bg,
          width: double.infinity,
          height: double.infinity,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(child: _buildCenter(style)),
                _buildStats(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenter(_PhaseStyle style) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconFor(_phase),
              size: 72,
              color: style.accent,
            ),
            SizedBox(height: 20),
            Text(
              _phase == _Phase.result && _lastMs != null
                  ? '$_lastMs ms'
                  : style.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: style.accent,
                fontSize: 40,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 12),
            Text(
              _phase == _Phase.result && _lastMs != null
                  ? _rating(_lastMs!)
                  : style.hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statTile('最近', _lastMs),
          _statTile('最佳', _bestMs),
          _statTile('平均', _avgMs),
          _statTile('次数', _history.isEmpty ? null : _history.length,
              unit: ''),
        ],
      ),
    );
  }

  Widget _statTile(String label, int? value, {String unit = 'ms'}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value == null ? '—' : '$value$unit',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  IconData _iconFor(_Phase phase) {
    switch (phase) {
      case _Phase.idle:
        return Icons.touch_app_rounded;
      case _Phase.waiting:
        return Icons.hourglass_top_rounded;
      case _Phase.ready:
        return Icons.bolt_rounded;
      case _Phase.tooEarly:
        return Icons.warning_amber_rounded;
      case _Phase.result:
        return Icons.emoji_events_rounded;
    }
  }

  /// 根据反应时间给出评级文案。
  String _rating(int ms) {
    if (ms < 200) return '⚡ 超神反应！';
    if (ms < 280) return '🔥 非常快';
    if (ms < 350) return '👍 不错';
    if (ms < 450) return '🙂 一般';
    return '🐢 再练练';
  }
}

/// 注册反应力测试 Demo
void registerReactionTestDemo() {
  demoRegistry.register(ReactionTestDemo());
}
