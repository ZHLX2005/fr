// demo 网格与逐项错峰入场动画。

import 'package:flutter/material.dart';

import '../../../../lab/lab_container.dart';
import '../lab_panel/const_lab_panel.dart';
import '../lab_perf_log.dart';
import 'demo_card.dart';

class DemoScrollRevealGrid extends StatefulWidget {
  const DemoScrollRevealGrid({
    super.key,
    required this.demos,
    required this.controller,
    required this.onDemoTap,
    required this.physics,
  });

  final List<MapEntry<String, DemoPage>> demos;
  final ScrollController controller;
  final ValueChanged<DemoPage> onDemoTap;
  final ScrollPhysics physics;

  @override
  State<DemoScrollRevealGrid> createState() => _DemoScrollRevealGridState();
}

class _DemoScrollRevealGridState extends State<DemoScrollRevealGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: kLabRevealDuration,
    );
    labPerfLog('grid reveal start itemCount=${widget.demos.length}');
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: widget.controller,
      physics: widget.physics,
      padding: const EdgeInsets.all(kLabGridPadding),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: kLabGridCrossAxisCount,
        mainAxisSpacing: kLabGridSpacing,
        crossAxisSpacing: kLabGridSpacing,
        childAspectRatio: kLabGridAspectRatio,
      ),
      itemCount: widget.demos.length,
      itemBuilder: (context, index) {
        final demo = widget.demos[index].value;
        return RevealItem(
          index: index,
          controller: _controller,
          child: DemoCard(
            title: demo.title,
            description: demo.description,
            onTap: () => widget.onDemoTap(demo),
          ),
        );
      },
    );
  }
}

class RevealItem extends StatefulWidget {
  const RevealItem({
    super.key,
    required this.index,
    required this.controller,
    required this.child,
  });

  final int index;
  final AnimationController controller;
  final Widget child;

  @override
  State<RevealItem> createState() => _RevealItemState();
}

class _RevealItemState extends State<RevealItem> {
  double get _delay =>
      (widget.index * kLabRevealDelayStep).clamp(0.0, kLabRevealMaxDelay);
  double get _dur => kLabRevealItemDuration;

  double _progress(double t) {
    final start = _delay;
    final end = start + _dur;
    if (t < start) return 0.0;
    if (t >= end) return 1.0;
    return Curves.easeOutCubic.transform((t - start) / (end - start));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final p = _progress(widget.controller.value);
        if (p >= 1.0) {
          return widget.child;
        }
        return Opacity(
          opacity: p,
          child: Transform.translate(
            offset: Offset(0, kLabRevealTranslateY * (1 - p)),
            child: widget.child,
          ),
        );
      },
    );
  }
}
