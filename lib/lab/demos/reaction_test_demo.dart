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

/// 主屏信号灯配色 —— **主题豁免**（登记见 docs/architecture/theme-channel-audit.md 2.3）。
///
/// 为什么固定：反应力测试的相位底色是交互指令本身（红 = 别点 / 绿 = 可以点），
/// 用户要在几百毫秒内靠颜色做判断，所以判据是「语义是否成立」而不是「是否跟随主题」。
/// 走 [ColorScheme] 在多数主题下会失效 ——
///   · 墨白：primary 与 onSurface 同为 #1A1A1A，ready 与 idle 底色完全相同，
///     「变绿」那一刻画面毫无变化，测试无法进行；
///   · 暮紫：ready(primary) 与 waiting(error) 同属紫粉色系，红绿语义同时失效；
///   · 粉雾海盐：ready(primary) 粉红比 waiting(error) 深红更「危险」，语义近似反转；
///   · 柠檬鼠尾草：ready(primary) 是柠檬黄，绿语义丢失。
/// 与 Torch 的补光输出色同类，属「规则视觉色 / 功能输出色」。
///
/// 前景与底色**成对固定**：若只固定底色而前景继续取 onSurface，
/// 会重演「底色与文字同色」的脱钩——旧实现中 idle/result 的提示文案正是因此全主题不可见。
class ReactionPalette {
  ReactionPalette._();

  /// 中性态（idle / result）底色
  static const Color neutralBg = Color(0xFF14171A);

  /// 中性态主前景（16.5:1）
  static const Color neutralFg = Color(0xFFF5F5F3);

  /// 中性态次级前景（11.3:1）
  static const Color neutralMuted = Color(0xFFCCCDCC);

  /// 中性态强调色（金，9.5:1），用于开始 / 成绩的图标与主文案
  static const Color neutralAccent = Color(0xFFE5B567);

  /// 等待态：红 = 别点（白字 6.5:1）
  static const Color stopBg = Color(0xFFB91C1C);

  /// 等待态主前景
  static const Color stopFg = Color(0xFFFFFFFF);

  /// 等待态次级前景（4.7:1）
  static const Color stopMuted = Color(0xFFF2D6D6);

  /// 就绪态：绿 = 可以点（亮绿 + 深字 7.3:1）
  static const Color goBg = Color(0xFF22C55E);

  /// 就绪态主前景
  static const Color goFg = Color(0xFF06240F);

  /// 就绪态次级前景（5.2:1）
  static const Color goMuted = Color(0xFF0B411D);

  /// 抢跳态：琥珀 = 太早（浅底 + 深字 8.6:1）
  static const Color earlyBg = Color(0xFFF5A524);

  /// 抢跳态主前景
  static const Color earlyFg = Color(0xFF241703);

  /// 抢跳态次级前景（5.9:1）
  static const Color earlyMuted = Color(0xFF4A3109);
}

/// 各阶段配色（底色 + 主/次前景 + 强调色）与文案统一管理，降低维护成本。
///
/// 每相位自带 [fg] / [muted] 两个不透明前景色，不靠 alpha 叠色：
/// 半透明文字叠在相位底色上会同时抬高两侧亮度、吃掉对比度，
/// 这正是旧实现（前景统一取 onSurface + 各种 alpha）读不出来的原因。
class _PhaseStyle {
  const _PhaseStyle({
    required this.bg,
    required this.fg,
    required this.muted,
    required this.title,
    required this.hint,
    this.accent,
  });

  /// 相位底色（固定信号灯色，不随主题）
  final Color bg;

  /// 主前景：统计数字、主文案（未指定 accent 时）
  final Color fg;

  /// 次级前景：提示文案、统计条标签
  final Color muted;

  /// 图标与主文案的强调色；缺省时用 [fg]
  final Color? accent;

  final String title;
  final String hint;

  /// 图标与主文案用色
  Color get emphasis => accent ?? fg;

  /// 统计条顶部分隔线：纯装饰、不承载文字，故允许半透明
  Color get divider => fg.withValues(alpha: 0.18);
}

/// 相位配色表：固定信号灯色，**刻意不读 BuildContext**（语义化色不跟随主题）。
///
/// 各相位对比度实测（文字 vs 底色）：
///   neutral  16.5:1 / 11.3:1   stop  6.5:1 / 4.7:1
///   go        7.3:1 /  5.2:1   early 8.6:1 / 5.9:1
const Map<_Phase, _PhaseStyle> _kPhaseStyles = {
  _Phase.idle: _PhaseStyle(
    bg: ReactionPalette.neutralBg,
    fg: ReactionPalette.neutralFg,
    muted: ReactionPalette.neutralMuted,
    accent: ReactionPalette.neutralAccent,
    title: '反应力测试',
    hint: '点击屏幕开始',
  ),
  _Phase.waiting: _PhaseStyle(
    bg: ReactionPalette.stopBg,
    fg: ReactionPalette.stopFg,
    muted: ReactionPalette.stopMuted,
    title: '等待绿色…',
    hint: '不要着急，变绿再点',
  ),
  _Phase.ready: _PhaseStyle(
    bg: ReactionPalette.goBg,
    fg: ReactionPalette.goFg,
    muted: ReactionPalette.goMuted,
    title: '点击！',
    hint: '越快越好',
  ),
  _Phase.tooEarly: _PhaseStyle(
    bg: ReactionPalette.earlyBg,
    fg: ReactionPalette.earlyFg,
    muted: ReactionPalette.earlyMuted,
    title: '太早了！',
    hint: '还没变绿，点击重试',
  ),
  _Phase.result: _PhaseStyle(
    bg: ReactionPalette.neutralBg,
    fg: ReactionPalette.neutralFg,
    muted: ReactionPalette.neutralMuted,
    accent: ReactionPalette.neutralAccent,
    title: '成绩',
    hint: '点击再来一次',
  ),
};

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
    final style = _kPhaseStyles[_phase]!;
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
                _buildStats(style),
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
              color: style.emphasis,
            ),
            SizedBox(height: 20),
            Text(
              _phase == _Phase.result && _lastMs != null
                  ? '$_lastMs ms'
                  : style.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: style.emphasis,
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
                color: style.muted,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 统计条文字直接取相位的 [fg] / [muted]：数字用主前景、标签用次级前景，
  /// 二者在该相位底色上的对比度均 ≥4.5:1（不再用主题 onSurface + alpha 叠色）。
  Widget _buildStats(_PhaseStyle style) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      // 不铺蒙层：蒙层会同时抬高两侧亮度、吃掉次级文字的对比度，
      // 改用一根发丝分隔线与相位区做视觉切分（纯装饰，不承载文字）。
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: style.divider, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statTile(style, '最近', _lastMs),
          _statTile(style, '最佳', _bestMs),
          _statTile(style, '平均', _avgMs),
          _statTile(style, '次数', _history.isEmpty ? null : _history.length,
              unit: ''),
        ],
      ),
    );
  }

  Widget _statTile(_PhaseStyle style, String label, int? value,
      {String unit = 'ms'}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value == null ? '—' : '$value$unit',
          style: TextStyle(
            color: style.fg,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: style.muted,
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
