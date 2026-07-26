// demo 网格：2 列固定网格 + 共享 RevealItem 入场动画。

import 'package:flutter/material.dart';

import '../../../../lab/lab_container.dart';
import '../lab_panel/const_lab_panel.dart';
import '../lab_perf_log.dart';
import '../reveal_item.dart';
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

// RevealItem 已提升为共享组件（../reveal_item.dart），游戏中心同用。
