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
      start: DateTime(2026, 4, 18, 9, 0),
      end: DateTime(2026, 4, 18, 10, 30),
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
      start: DateTime(2026, 4, 18, 10, 0),
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

  // 预设色块颜色
  static const _presetColors = [
    0xFF6366F1, // Indigo
    0xFF8B5CF6, // Violet
    0xFFF97316, // Orange
    0xFF14B8A6, // Teal
    0xFFEF4444, // Red
    0xFF06B6D4, // Cyan
    0xFFF59E0B, // Amber
    0xFF10B981, // Emerald
    0xFFEC4899, // Pink
    0xFF3B82F6, // Blue
  ];

  int _nextId = 100;

  void _showAddEventSheet() {
    // 初始值：当前时间向下取整到10分钟
    final now = DateTime.now();
    var startMinutes = (now.hour * 60 + now.minute) ~/ 10 * 10;
    var endMinutes = startMinutes + 60; // 默认1小时
    var selectedLane = DoubleTimeLane.plan;
    var selectedColor = _presetColors[0];
    var titleController = TextEditingController(text: 'New Event');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 顶部拖拽条
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // 标题栏
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        const Text(
                          '添加事件',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('取消'),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 标题输入
                          _SectionLabel('事件名称'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: titleController,
                            decoration: InputDecoration(
                              hintText: '输入事件名称',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // 车道选择
                          _SectionLabel('时间轴'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _LaneChip(
                                label: 'Plan',
                                color: const Color(0xFF6366F1),
                                selected: selectedLane == DoubleTimeLane.plan,
                                onTap: () =>
                                    setSheetState(() => selectedLane = DoubleTimeLane.plan),
                              ),
                              const SizedBox(width: 12),
                              _LaneChip(
                                label: 'Actual',
                                color: const Color(0xFFF97316),
                                selected:
                                    selectedLane == DoubleTimeLane.actual,
                                onTap: () => setSheetState(
                                    () => selectedLane = DoubleTimeLane.actual),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // 开始时间滚动选择
                          _SectionLabel('开始时间'),
                          const SizedBox(height: 8),
                          _TimeScrollPicker(
                            initialMinutes: startMinutes,
                            onChanged: (v) =>
                                setSheetState(() => startMinutes = v),
                          ),
                          const SizedBox(height: 20),

                          // 结束时间滚动选择
                          _SectionLabel('结束时间'),
                          const SizedBox(height: 8),
                          _TimeScrollPicker(
                            initialMinutes: endMinutes,
                            onChanged: (v) =>
                                setSheetState(() => endMinutes = v),
                          ),
                          const SizedBox(height: 20),

                          // 颜色选择
                          _SectionLabel('色块颜色'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _presetColors.map((c) {
                              final isSelected = c == selectedColor;
                              return GestureDetector(
                                onTap: () =>
                                    setSheetState(() => selectedColor = c),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Color(c),
                                    shape: BoxShape.circle,
                                    border: isSelected
                                        ? Border.all(
                                            color: Colors.black, width: 3)
                                        : null,
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: Color(c)
                                                  .withValues(alpha: 0.4),
                                              blurRadius: 8,
                                              spreadRadius: 2,
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check,
                                          color: Colors.white, size: 18)
                                      : null,
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 28),

                          // 添加按钮
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: () {
                                // 校验：结束必须大于开始
                                if (endMinutes <= startMinutes) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('结束时间必须大于开始时间')),
                                  );
                                  return;
                                }

                                final event = DoubleTimeEvent(
                                  id: 'evt_${_nextId++}',
                                  lane: selectedLane,
                                  start: DateTime(
                                    _day.year,
                                    _day.month,
                                    _day.day,
                                    startMinutes ~/ 60,
                                    startMinutes % 60,
                                  ),
                                  end: DateTime(
                                    _day.year,
                                    _day.month,
                                    _day.day,
                                    endMinutes ~/ 60,
                                    endMinutes % 60,
                                  ),
                                  colorArgb: selectedColor,
                                  title: titleController.text.isEmpty
                                      ? 'Untitled'
                                      : titleController.text,
                                );

                                setState(() => _events.add(event));
                                Navigator.pop(sheetContext);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(selectedColor),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                '添加',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          // 底部安全区
                          SizedBox(
                              height: MediaQuery.of(context).padding.bottom),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteEvent(DoubleTimeEvent event) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('删除 "${event.title}"？'),
        content: Text(
          '${_fmtTime(event.start)} – ${_fmtTime(event.end)} 的 ${event.lane == DoubleTimeLane.plan ? "Plan" : "Actual"} 事件将被移除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() => _events.removeWhere((e) => e.id == event.id));
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

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
          // 图例 + 事件列表
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const _LegendChip(label: 'Plan', color: Color(0xFF6366F1)),
                const _LegendChip(label: 'Actual', color: Color(0xFFF97316)),
                _LegendChip(
                  label: '${_events.length} events',
                  color: const Color(0xFF14B8A6),
                ),
              ],
            ),
          ),
          // 事件列表（可点击删除）
          if (_events.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: _events.map((evt) {
                  return _EventListTile(
                    event: evt,
                    onTap: () => _confirmDeleteEvent(evt),
                  );
                }).toList(),
              ),
            ),
          // 时间轴
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
      // 添加按钮
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddEventSheet,
        backgroundColor: const Color(0xFF6366F1),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// ─── 事件列表条目（点击删除）──────────────────────────

class _EventListTile extends StatelessWidget {
  final DoubleTimeEvent event;
  final VoidCallback onTap;

  const _EventListTile({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final startStr =
        '${event.start.hour.toString().padLeft(2, '0')}:${event.start.minute.toString().padLeft(2, '0')}';
    final endStr =
        '${event.end.hour.toString().padLeft(2, '0')}:${event.end.minute.toString().padLeft(2, '0')}';
    final duration = event.end.difference(event.start).inMinutes;
    final laneLabel = event.lane == DoubleTimeLane.plan ? 'Plan' : 'Actual';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Color(event.colorArgb).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            // 色块圆点
            Container(
              width: 8,
              height: 32,
              decoration: BoxDecoration(
                color: Color(event.colorArgb),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$laneLabel · $startStr – $endStr · ${duration}min',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            // 删除提示
            Icon(Icons.close, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

// ─── 10分钟粒度时间滚动选择器 ──────────────────────

class _TimeScrollPicker extends StatefulWidget {
  final int initialMinutes; // 0..1430 (23:50)
  final ValueChanged<int> onChanged;

  const _TimeScrollPicker({
    required this.initialMinutes,
    required this.onChanged,
  });

  @override
  State<_TimeScrollPicker> createState() => _TimeScrollPickerState();
}

class _TimeScrollPickerState extends State<_TimeScrollPicker> {
  late final FixedExtentScrollController _controller;
  static const _itemHeight = 44.0;
  static const _visibleCount = 5;

  // 0:00 ~ 23:50，步长10分钟 → 144个选项
  static const _totalSlots = 144;

  @override
  void initState() {
    super.initState();
    final index = widget.initialMinutes ~/ 10;
    _controller = FixedExtentScrollController(initialItem: index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _label(int index) {
    final minutes = index * 10;
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _itemHeight * _visibleCount,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Stack(
        children: [
          // 高亮选中行
          Center(
            child: Container(
              height: _itemHeight,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          // 列表
          ListWheelScrollView.useDelegate(
            controller: _controller,
            itemExtent: _itemHeight,
            diameterRatio: 2.5,
            perspective: 0.003,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (index) {
              widget.onChanged(index * 10);
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: _totalSlots,
              builder: (context, index) {
                if (index < 0 || index >= _totalSlots) return null;
                return Center(
                  child: Text(
                    _label(index),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
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

// ─── 小组件 ──────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF64748B),
        letterSpacing: 0.3,
      ),
    );
  }
}

class _LaneChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _LaneChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: selected ? Colors.white : color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF334155),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
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
