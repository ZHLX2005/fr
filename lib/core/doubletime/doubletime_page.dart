import 'package:flutter/material.dart';

import 'doubletime_mapper.dart';
import 'doubletime_models.dart';
import 'doubletime_painter.dart';

class DoubleTimePage extends StatefulWidget {
  const DoubleTimePage({super.key});

  @override
  State<DoubleTimePage> createState() => _DoubleTimePageState();
}

class _DoubleTimePageState extends State<DoubleTimePage> {
  late final DateTime _day = DateTime(2026, 4, 18);
  bool _focusActual = false;

  late final List<DoubleTimeEvent> _events = <DoubleTimeEvent>[
    DoubleTimeEvent(
      id: 'plan_1',
      lane: DoubleTimeLane.plan,
      start: DateTime(2026, 4, 18, 9, 15),
      end: DateTime(2026, 4, 18, 10, 45),
      colorArgb: 0xFF6366F1,
      title: 'Deep Work',
    ),
    DoubleTimeEvent(
      id: 'plan_2',
      lane: DoubleTimeLane.plan,
      start: DateTime(2026, 4, 18, 14, 0),
      end: DateTime(2026, 4, 18, 15, 30),
      colorArgb: 0xFF8B5CF6,
      title: 'Product Review',
    ),
    DoubleTimeEvent(
      id: 'actual_1',
      lane: DoubleTimeLane.actual,
      start: DateTime(2026, 4, 18, 9, 0),
      end: DateTime(2026, 4, 18, 10, 0),
      colorArgb: 0xFFF97316,
      title: 'Standup + Sync',
    ),
    DoubleTimeEvent(
      id: 'actual_2',
      lane: DoubleTimeLane.actual,
      start: DateTime(2026, 4, 18, 10, 15),
      end: DateTime(2026, 4, 18, 12, 0),
      colorArgb: 0xFF14B8A6,
      title: 'Feature Build',
    ),
    DoubleTimeEvent(
      id: 'actual_3',
      lane: DoubleTimeLane.actual,
      start: DateTime(2026, 4, 18, 14, 30),
      end: DateTime(2026, 4, 18, 16, 0),
      colorArgb: 0xFFEF4444,
      title: 'Bug Fix',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final allocations = mapAllEvents(_events);
    final size = MediaQuery.of(context).size;
    final laneWidth = _focusActual
        ? size.width - 56 - 24
        : (size.width - 56 - 12 - 24) / 2;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text('Double Time'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _focusActual = !_focusActual;
              });
            },
            child: Text(_focusActual ? 'Show Plan' : 'Focus Actual'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _LegendChip(label: 'Plan', color: Color(0xFF6366F1)),
                _LegendChip(label: 'Actual', color: Color(0xFFF97316)),
                _LegendChip(label: 'Grid = 1 hour', color: Color(0xFF14B8A6)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '输入 start/end，映射到每小时格内的占用比例。当前 demo 只演示最小可用渲染与聚焦模式。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: CustomPaint(
                size: Size(size.width - 24, 24 * 56 + 40),
                painter: DualTimelinePainter(
                  day: _day,
                  allocations: allocations,
                  laneWidth: laneWidth,
                  hidePlanLane: _focusActual,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
