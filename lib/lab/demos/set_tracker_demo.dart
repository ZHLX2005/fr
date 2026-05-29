import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'set_tracker/const_set_tracker.dart';
import 'set_tracker/set_tracker_ring_painter.dart';

/// 训练组追踪器 Demo
/// 环形选择主题 + 多巴胺记录按钮 + 组数统计
class SetTrackerDemo extends DemoPage {
  @override
  String get title => '组数追踪';

  @override
  String get description => '环形选择训练主题，快捷记录每组动作';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const SetTrackerPage();
  }
}

/// 单次记录
class _SetRecord {
  final String id;
  final String themeId;
  final String themeLabel;
  final DateTime time;
  int reps;
  double weight;

  _SetRecord({
    required this.id,
    required this.themeId,
    required this.themeLabel,
    required this.time,
    this.reps = 10,
    this.weight = 0,
  });
}

class SetTrackerPage extends StatefulWidget {
  const SetTrackerPage({super.key});

  @override
  State<SetTrackerPage> createState() => _SetTrackerPageState();
}

class _SetTrackerPageState extends State<SetTrackerPage>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController(viewportFraction: 0.28);
  final List<_SetRecord> _records = [];

  int _selectedIndex = 0;
  int _currentReps = 10;
  double _currentWeight = 20.0;
  bool _isRecording = false;

  late AnimationController _recordAnimController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _recordAnimController = AnimationController(
      vsync: this,
      duration: SetTrackerConst.buttonPressDuration,
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: SetTrackerConst.recordPulseDuration,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _recordAnimController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  int get _todaySetCount {
    final now = DateTime.now();
    return _records.where((r) {
      return r.time.year == now.year &&
          r.time.month == now.month &&
          r.time.day == now.day;
    }).length;
  }

  int _todayCountFor(String themeId) {
    final now = DateTime.now();
    return _records.where((r) {
      return r.themeId == themeId &&
          r.time.year == now.year &&
          r.time.month == now.month &&
          r.time.day == now.day;
    }).length;
  }

  void _recordSet() async {
    if (_isRecording) return;
    setState(() => _isRecording = true);

    await _recordAnimController.forward();
    await _recordAnimController.reverse();

    final theme = SetTrackerConst.themes[_selectedIndex];
    final record = _SetRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      themeId: theme.id,
      themeLabel: theme.label,
      time: DateTime.now(),
      reps: _currentReps,
      weight: _currentWeight,
    );

    setState(() {
      _records.insert(0, record);
      _isRecording = false;
    });

    _pulseController.forward(from: 0);
  }

  void _deleteRecord(String id) {
    setState(() {
      _records.removeWhere((r) => r.id == id);
    });
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HistorySheet(
        records: _records,
        onDelete: _deleteRecord,
        onClear: () => setState(() => _records.clear()),
      ),
    );
  }

  void _adjustReps(int delta) {
    setState(() {
      _currentReps = (_currentReps + delta).clamp(1, 100);
    });
  }

  void _adjustWeight(double delta) {
    setState(() {
      _currentWeight = (_currentWeight + delta).clamp(0, 500);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = SetTrackerConst.themes[_selectedIndex];

    return Scaffold(
      backgroundColor: SetTrackerConst.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // ===== 自定义头部 =====
            _buildHeader(),

            // ===== 环形选择器区域 =====
            Expanded(
              flex: 5,
              child: LayoutBuilder(
                builder: (_, constraints) {
                  final size = constraints.biggest;
                  final cx = size.width / 2;
                  final cy = size.height * 1.3;
                  final radius = size.shortestSide * 0.72;

                  return Stack(
                    children: [
                      // 轨道绘制
                      CustomPaint(
                        size: size,
                        painter: SetTrackerRingPainter(
                          cx: cx,
                          cy: cy,
                          radius: radius,
                          startAngle: SetTrackerConst.arcStartAngle,
                          sweepAngle: SetTrackerConst.arcSweepAngle,
                          selectedIndex: _selectedIndex,
                          themeCount: SetTrackerConst.themes.length,
                        ),
                      ),

                      // 主题标签层
                      _ThemeLabelLayer(
                        controller: _pageController,
                        cx: cx,
                        cy: cy,
                        radius: radius,
                        startAngle: SetTrackerConst.arcStartAngle,
                        sweepAngle: SetTrackerConst.arcSweepAngle,
                        visibleCount: SetTrackerConst.arcVisibleCount,
                      ),

                      // 手势层
                      PageView.builder(
                        controller: _pageController,
                        itemCount: SetTrackerConst.themes.length,
                        onPageChanged: (i) => setState(() => _selectedIndex = i),
                        itemBuilder: (_, __) => const SizedBox.expand(),
                      ),
                    ],
                  );
                },
              ),
            ),

            // ===== 当前主题信息 + 参数调节 =====
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 当前主题标签
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: theme.linearGradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: theme.gradient[0].withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(theme.icon, color: Colors.white, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            theme.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 参数调节行
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 重量
                        _buildParamCard(
                          label: '重量',
                          value: '${_currentWeight.toStringAsFixed(1)} kg',
                          onDecrease: () => _adjustWeight(-2.5),
                          onIncrease: () => _adjustWeight(2.5),
                          color: theme.gradient[0],
                        ),
                        const SizedBox(width: 16),
                        // 次数
                        _buildParamCard(
                          label: '次数',
                          value: '$_currentReps',
                          onDecrease: () => _adjustReps(-1),
                          onIncrease: () => _adjustReps(1),
                          color: theme.gradient[1],
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // 记录按钮
                    _buildRecordButton(theme),
                  ],
                ),
              ),
            ),

            // ===== 今日统计 =====
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SetTrackerConst.cardBg,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: SetTrackerConst.shadowColor,
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '今日统计',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: SetTrackerConst.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6B6B).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '共 $_todaySetCount 组',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF6B6B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        children: SetTrackerConst.themes.map((t) {
                          final count = _todayCountFor(t.id);
                          final isActive = count > 0;
                          return Expanded(
                            child: Column(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    gradient: isActive ? t.linearGradient : null,
                                    color: isActive ? null : const Color(0xFFF0F0F2),
                                    shape: BoxShape.circle,
                                    boxShadow: isActive
                                        ? [
                                            BoxShadow(
                                              color: t.gradient[0].withValues(alpha: 0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$count',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isActive ? Colors.white : SetTrackerConst.textMuted,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  t.label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isActive ? SetTrackerConst.textPrimary : SetTrackerConst.textMuted,
                                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '训练打卡',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: SetTrackerConst.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '选择主题，记录每一组',
                style: TextStyle(
                  fontSize: 13,
                  color: SetTrackerConst.textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          // 历史记录按钮
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            elevation: 2,
            shadowColor: SetTrackerConst.shadowColor,
            child: InkWell(
              onTap: _showHistory,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(10),
                child: const Icon(
                  Icons.history,
                  color: SetTrackerConst.textPrimary,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildParamCard({
    required String label,
    required String value,
    required VoidCallback onDecrease,
    required VoidCallback onIncrease,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: SetTrackerConst.shadowColor,
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: SetTrackerConst.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildParamButton(onDecrease, Icons.remove, color),
              const SizedBox(width: 12),
              _buildParamButton(onIncrease, Icons.add, color),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParamButton(VoidCallback onTap, IconData icon, Color color) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  Widget _buildRecordButton(WorkoutTheme theme) {
    return AnimatedBuilder(
      animation: _recordAnimController,
      builder: (_, __) {
        final scale = 1.0 - _recordAnimController.value * 0.12;
        return Transform.scale(
          scale: scale,
          child: GestureDetector(
            onTap: _recordSet,
            child: Container(
              width: SetTrackerConst.recordButtonSize,
              height: SetTrackerConst.recordButtonSize,
              decoration: BoxDecoration(
                gradient: theme.linearGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: theme.gradient[0].withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: theme.gradient[1].withValues(alpha: 0.2),
                    blurRadius: 40,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add,
                      color: Colors.white,
                      size: 36,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isRecording ? '记录中...' : '记录一组',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 弧线主题标签层
class _ThemeLabelLayer extends StatelessWidget {
  final PageController controller;
  final double cx;
  final double cy;
  final double radius;
  final double startAngle;
  final double sweepAngle;
  final int visibleCount;

  const _ThemeLabelLayer({
    required this.controller,
    required this.cx,
    required this.cy,
    required this.radius,
    required this.startAngle,
    required this.sweepAngle,
    required this.visibleCount,
  });

  @override
  Widget build(BuildContext context) {
    final k = (visibleCount - 1) / 2;

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.hasClients ? (controller.page ?? 0) : 0.0;
        final children = <Widget>[];

        for (int i = 0; i < SetTrackerConst.themes.length; i++) {
          final d = i - t;
          if (d.abs() > k + 1) continue;

          final u = ((d + k) / (2 * k)).clamp(0.0, 1.0);
          final theta = startAngle + sweepAngle * u;

          final x = cx + radius * math.cos(theta);
          final y = cy + radius * math.sin(theta);

          final nx = x - cx;
          final ny = y - cy;
          final len = math.sqrt(nx * nx + ny * ny);
          const lift = 42.0;

          final ox = x + (nx / len) * lift;
          final oy = y + (ny / len) * lift;

          final emphasis = (1 - (d.abs() / k)).clamp(0.0, 1.0);
          final scale = 0.55 + 0.55 * emphasis;
          final opacity = 0.3 + 0.7 * emphasis;
          final theme = SetTrackerConst.themes[i];
          final isCenter = emphasis > 0.7;

          children.add(
            Positioned(
              left: ox - 40,
              top: oy - 32,
              width: 80,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: isCenter ? 56 : 44,
                        height: isCenter ? 56 : 44,
                        decoration: BoxDecoration(
                          gradient: isCenter ? theme.linearGradient : null,
                          color: isCenter ? null : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: isCenter
                              ? [
                                  BoxShadow(
                                    color: theme.gradient[0].withValues(alpha: 0.4),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                          border: isCenter
                              ? null
                              : Border.all(
                                  color: const Color(0xFFE8E8EC),
                                  width: 2,
                                ),
                        ),
                        child: Center(
                          child: Icon(
                            theme.icon,
                            size: isCenter ? 26 : 20,
                            color: isCenter ? Colors.white : SetTrackerConst.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        theme.label,
                        style: TextStyle(
                          color: isCenter ? theme.gradient[0] : SetTrackerConst.textSecondary,
                          fontSize: isCenter ? 14 : 12,
                          fontWeight: isCenter ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return Stack(children: children);
      },
    );
  }
}

/// 历史记录底部弹窗
class _HistorySheet extends StatelessWidget {
  final List<_SetRecord> records;
  final ValueChanged<String> onDelete;
  final VoidCallback onClear;

  const _HistorySheet({
    required this.records,
    required this.onDelete,
    required this.onClear,
  });

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: SetTrackerConst.bgColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // 把手
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                const Text(
                  '训练记录',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: SetTrackerConst.textPrimary,
                  ),
                ),
                const Spacer(),
                if (records.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          title: const Text('清空记录'),
                          content: const Text('确定清空所有训练记录？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                Navigator.pop(context);
                                onClear();
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: const Text('清空'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('清空'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),

          // 记录列表
          Expanded(
            child: records.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.fitness_center,
                          size: 56,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '还没有记录',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '开始你的第一组训练吧！',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final record = records[index];
                      final theme = SetTrackerConst.themes.firstWhere(
                        (t) => t.id == record.themeId,
                        orElse: () => SetTrackerConst.themes[0],
                      );
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: theme.linearGradient,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Icon(theme.icon, color: Colors.white, size: 20),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    theme.label,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: SetTrackerConst.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${record.weight.toStringAsFixed(1)} kg × ${record.reps} 次',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: SetTrackerConst.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _formatTime(record.time),
                              style: const TextStyle(
                                fontSize: 12,
                                color: SetTrackerConst.textMuted,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Material(
                              color: Colors.red.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              child: InkWell(
                                onTap: () => onDelete(record.id),
                                borderRadius: BorderRadius.circular(8),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                            ),
                          ],
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

void registerSetTrackerDemo() {
  demoRegistry.register(SetTrackerDemo());
}
