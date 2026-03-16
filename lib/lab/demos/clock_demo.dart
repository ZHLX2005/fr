import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../lab_container.dart';
import '../models/lab_clock.dart';
import '../providers/lab_clock_provider.dart';

/// 时钟 Demo
class ClockDemo extends DemoPage {
  @override
  String get title => '时钟';

  @override
  String get description => '网格时钟，支持倒计时功能';

  @override
  Widget buildPage(BuildContext context) {
    return const _ClockDemoPage();
  }
}

class _ClockDemoPage extends StatefulWidget {
  const _ClockDemoPage();

  @override
  State<_ClockDemoPage> createState() => _ClockDemoPageState();
}

class _ClockDemoPageState extends State<_ClockDemoPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LabClockProvider>().loadClocks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('时钟'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addClock(context),
          ),
        ],
      ),
      body: Consumer<LabClockProvider>(
        builder: (context, provider, child) {
          if (provider.clocks.isEmpty) {
            return _buildEmpty(context);
          }
          return _buildClockGrid(context, provider.clocks);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addClock(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer_outlined, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('暂无时钟', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _addClock(context),
            icon: const Icon(Icons.add),
            label: const Text('添加时钟'),
          ),
        ],
      ),
    );
  }

  Widget _buildClockGrid(BuildContext context, List<LabClock> clocks) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.0,
      ),
      itemCount: clocks.length,
      itemBuilder: (context, index) => _ClockCard(
        clock: clocks[index],
        onTap: () => _editClock(context, clocks[index]),
        onDelete: () => _deleteClock(context, clocks[index]),
        onStart: () => context.read<LabClockProvider>().startCountdown(clocks[index].id),
        onPause: () => context.read<LabClockProvider>().pauseCountdown(clocks[index].id),
        onReset: () => context.read<LabClockProvider>().resetCountdown(clocks[index].id),
      ),
    );
  }

  void _addClock(BuildContext context) {
    _showClockEditor(context, null);
  }

  void _editClock(BuildContext context, LabClock clock) {
    _showClockEditor(context, clock);
  }

  void _deleteClock(BuildContext context, LabClock clock) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除时钟'),
        content: Text('确定删除 "${clock.title}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              context.read<LabClockProvider>().deleteClock(clock.id);
              Navigator.pop(ctx);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showClockEditor(BuildContext context, LabClock? clock) {
    final titleController = TextEditingController(text: clock?.title ?? '');
    final descController = TextEditingController(text: clock?.description ?? '');
    int hours = clock != null ? (clock.durationSeconds ?? 0) ~/ 3600 : 0;
    int minutes = clock != null ? ((clock.durationSeconds ?? 0) % 3600) ~/ 60 : 5;
    int seconds = clock != null ? (clock.durationSeconds ?? 0) % 60 : 0;
    String selectedColor = clock?.color ?? '#2196F3';

    final colors = ['#2196F3', '#4CAF50', '#FF9800', '#E91E63', '#9C27B0', '#00BCD4', '#795548', '#607D8B'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(clock == null ? '添加时钟' : '编辑时钟', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(controller: titleController, decoration: const InputDecoration(labelText: '标题', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: descController, decoration: const InputDecoration(labelText: '描述', border: OutlineInputBorder()), maxLines: 2),
              const SizedBox(height: 12),
              const Text('倒计时时长:', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 360;
                  if (isWide) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _timePicker('时', hours, 23, (v) => setState(() => hours = v)),
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text(' : ', style: TextStyle(fontSize: 16))),
                        _timePicker('分', minutes, 59, (v) => setState(() => minutes = v)),
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text(' : ', style: TextStyle(fontSize: 16))),
                        _timePicker('秒', seconds, 59, (v) => setState(() => seconds = v)),
                      ],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _timePicker('时', hours, 23, (v) => setState(() => hours = v)),
                      const Text(' : ', style: TextStyle(fontSize: 14)),
                      _timePicker('分', minutes, 59, (v) => setState(() => minutes = v)),
                      const Text(' : ', style: TextStyle(fontSize: 14)),
                      _timePicker('秒', seconds, 59, (v) => setState(() => seconds = v)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              const Text('颜色:', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  // 计算每行显示几个颜色，实现均衡分布
                  final itemWidth = 36.0 + 8.0; // 颜色球宽度 + 间距
                  final maxPerRow = (constraints.maxWidth / itemWidth).floor().clamp(1, 8);
                  final rows = (colors.length / maxPerRow).ceil();
                  final itemsPerRow = (colors.length / rows).ceil();

                  return Column(
                    children: List.generate(rows, (rowIndex) {
                      final start = rowIndex * itemsPerRow;
                      final end = (start + itemsPerRow).clamp(0, colors.length);
                      final rowColors = colors.sublist(start, end);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: rowColors.map((c) {
                            final isSelected = c == selectedColor;
                            return GestureDetector(
                              onTap: () => setState(() => selectedColor = c),
                              child: Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: Color(int.parse(c.replaceFirst('#', '0xFF'))),
                                  shape: BoxShape.circle,
                                  border: isSelected ? Border.all(color: Colors.black, width: 3) : null,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    }),
                  );
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final provider = context.read<LabClockProvider>();
                    final totalSeconds = hours * 3600 + minutes * 60 + seconds;
                    if (clock == null) {
                      provider.createClock(
                        title: titleController.text.isEmpty ? '新时钟' : titleController.text,
                        description: descController.text,
                        durationSeconds: totalSeconds,
                        color: selectedColor,
                      );
                    } else {
                      provider.updateClock(
                        id: clock.id,
                        title: titleController.text,
                        description: descController.text,
                        durationSeconds: totalSeconds,
                        color: selectedColor,
                      );
                    }
                    Navigator.pop(ctx);
                  },
                  child: Text(clock == null ? '添加' : '保存'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timePicker(String label, int value, int max, Function(int) onChanged) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        SizedBox(
          height: 80,
          width: 50,
          child: ListWheelScrollView.useDelegate(
            itemExtent: 28,
            perspective: 0.003,
            diameterRatio: 1.2,
            physics: const FixedExtentScrollPhysics(),
            controller: FixedExtentScrollController(initialItem: value),
            onSelectedItemChanged: (index) => onChanged(index),
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: max + 1,
              builder: (context, index) {
                final isSelected = index == value;
                return Center(
                  child: Text(
                    index.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: isSelected ? 18 : 14,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.black : Colors.grey,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ClockCard extends StatelessWidget {
  final LabClock clock;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onReset;

  const _ClockCard({
    required this.clock,
    required this.onTap,
    required this.onDelete,
    required this.onStart,
    required this.onPause,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clockColor = Color(int.parse(clock.color?.replaceFirst('#', '0xFF') ?? '0xFF2196F3'));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [clockColor.withOpacity(0.1), clockColor.withOpacity(0.05)],
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Expanded(
                    child: Text(clock.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  GestureDetector(
                    onTap: onDelete,
                    child: Icon(Icons.close, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
                ],
              ),
              // 描述
              if (clock.description.isNotEmpty)
                Text(clock.description, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.5)), maxLines: 1, overflow: TextOverflow.ellipsis),
              const Spacer(),
              // 时间显示
              Center(
                child: Text(_formatTime(clock.remainingSeconds), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: clockColor)),
              ),
              const Spacer(),
              // 按钮
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: clock.isRunning ? onPause : onStart,
                      child: Icon(clock.isRunning ? Icons.pause_circle : Icons.play_circle, size: 28, color: clockColor),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(onTap: onReset, child: Icon(Icons.refresh, size: 24, color: theme.colorScheme.onSurface.withOpacity(0.6))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

void registerClockDemo() {
  demoRegistry.register(ClockDemo());
}
