import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/context/colors.dart';
import '../../lab_container.dart';
import 'const_notification_pull.dart';
import 'notification_pull_card.dart';

/// 网易云通知卡 · 下拉展开 Demo。
///
/// 复刻网易云音乐通知卡的连续下拉展开动效：
/// 折叠三行 → 下拉对齐头部 → 行距拉开 → 三条同时展开正文、摘要淡去
/// → 继续下拉露出第四/五条。
///
/// 几何与 docs/prototypes/notification-pull-expand.html 一一对应。
class NotificationPullDemo extends DemoPage {
  @override
  String get title => '通知卡下拉';

  @override
  String get slug => 'notification-pull';

  @override
  String get description => '网易云通知卡 · 连续下拉展开动效复刻';

  @override
  bool get preferFullScreen => false;

  @override
  Widget buildPage(BuildContext context) {
    return const NotificationPullDemoPage();
  }
}

void registerNotificationPullDemo() {
  demoRegistry.register(NotificationPullDemo());
}

/// Demo 页面：手机壳 + 通知卡 + 档位切换器。
class NotificationPullDemoPage extends StatefulWidget {
  const NotificationPullDemoPage({super.key});

  @override
  State<NotificationPullDemoPage> createState() =>
      _NotificationPullDemoPageState();
}

class _NotificationPullDemoPageState extends State<NotificationPullDemoPage> {
  /// 当前直达档位。null = 折叠态（默认）。
  ///
  /// 卡片只在 initState 读一次 initialStage，所以切换档位时靠给卡片换
  /// ValueKey 强制重建 State。
  String? _stage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scheme.surface,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: _PhoneFrame(stage: _stage),
                ),
              ),
            ),
            _StageSwitcher(
              stage: _stage,
              onChanged: (String? s) => setState(() => _stage = s),
            ),
          ],
        ),
      ),
    );
  }
}

/// 档位切换器：折叠 / 三条 / 四条 / 五条。
class _StageSwitcher extends StatelessWidget {
  const _StageSwitcher({required this.stage, required this.onChanged});

  final String? stage;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Wrap(
        spacing: 8,
        alignment: WrapAlignment.center,
        children: <Widget>[
          _chip(context, '折叠', stage == null, () => onChanged(null)),
          for (final String key in kStagePresets)
            _chip(
              context,
              kStageLabels[key] ?? key,
              stage == key,
              () => onChanged(key),
            ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    bool active,
    VoidCallback onTap,
  ) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Material(
      color: active ? cs.primaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 手机壳（390×844）。壁纸 / 蒙版 / 卡片布局对齐 HTML 原型。
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.stage});

  /// 直达档位（null = 折叠态）。
  ///
  /// 卡片只在 initState 读一次 initialStage，所以靠换 ValueKey 强制重建。
  final String? stage;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 390,
      height: 844,
      child: MediaQuery.withNoTextScaling(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(46),
          child: Stack(
            children: <Widget>[
              const Positioned.fill(child: _Wallpaper()),
              const Positioned.fill(child: _Scrim()),
              Positioned(
                top: 146,
                left: 14,
                right: 14,
                child: NotificationPullCard(
                  key: ValueKey<String>('card-$stage'),
                  initialStage: stage,
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 130,
                child: _Hint(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 壁纸：多层径向光斑 + 线性底色，整体模糊后放大——对应 HTML 的 .wall。
class _Wallpaper extends StatelessWidget {
  const _Wallpaper();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 34, sigmaY: 34),
        child: Transform.scale(
          scale: 1.18,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-0.85, -1),
                    end: Alignment(0.85, 1),
                    colors: <Color>[
                      Color(0xFF948AAB),
                      Color(0xFFBAB0C6),
                      Color(0xFFB3A1A0),
                      Color(0xFF948AA4),
                    ],
                    stops: <double>[0, .38, .72, 1],
                  ),
                ),
              ),
              _blob(const Alignment(-0.68, -0.88), .92, .68, 0xFFAB98C4),
              _blob(const Alignment(0.64, -0.82), .84, .60, 0xFF7EA0B8),
              _blob(const Alignment(-0.08, -0.20), 1.16, .80, 0xFFDED5E6),
              _blob(const Alignment(-0.72, 0.36), .92, .68, 0xFFA3B598),
              _blob(const Alignment(0.76, 0.48), 1.04, .80, 0xFFCB9A90),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blob(Alignment alignment, double wf, double hf, int rgb) {
    final Color color = Color(rgb);
    return Align(
      alignment: alignment,
      child: FractionallySizedBox(
        widthFactor: wf,
        heightFactor: hf,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: <Color>[color, color.withAlpha(0)],
              stops: const <double>[0, .62],
            ),
          ),
        ),
      ),
    );
  }
}

/// 蒙版：上下压暗，让白字读得出来。
class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x5C100D16), Color(0x3D100D16), Color(0x70100D16)],
          stops: <double>[0, .28, 1],
        ),
      ),
    );
  }
}

/// 底部「下拉展开 · 上推收起」提示。
class _Hint extends StatefulWidget {
  const _Hint();

  @override
  State<_Hint> createState() => _HintState();
}

class _HintState extends State<_Hint> with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedBuilder(
          animation: _bob,
          builder: (BuildContext context, Widget? child) {
            return Transform.translate(
              offset: Offset(0, -2 + 5 * Curves.easeInOut.transform(_bob.value)),
              child: child,
            );
          },
          child: const Opacity(
            opacity: .7,
            child: CustomPaint(size: Size(14, 14), painter: _DownArrowPainter()),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '下拉展开 · 上推收起',
          style: TextStyle(
            fontSize: 11.5,
            letterSpacing: 1.2,
            color: Color(0x8CFFFFFF),
            fontFamilyFallback: kFontFallback,
          ),
        ),
      ],
    );
  }
}

class _DownArrowPainter extends CustomPainter {
  const _DownArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(7, 1.5)
        ..lineTo(7, 12.5),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(2.3, 8.2)
        ..lineTo(7, 12.5)
        ..lineTo(11.7, 8.2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
