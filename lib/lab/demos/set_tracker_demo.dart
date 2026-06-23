import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'set_tracker/const_set_tracker.dart';
import 'set_tracker/set_tracker_ring_painter.dart';

/// 训练组追踪器 Demo
/// 双轮盘布局：上弧圆心在上（向下拱），下弧圆心在下（向上拱）
class SetTrackerDemo extends DemoPage {
  @override
  String get title => '组数追踪';

  @override
  String get description => '双轮盘选择器，上选类型下选次数，一键记录';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const SetTrackerPage();
  }
}

class _SetRecord {
  final String id;
  final String themeId;
  final String themeLabel;
  final String repsValue;
  final DateTime time;

  _SetRecord({
    required this.id,
    required this.themeId,
    required this.themeLabel,
    required this.repsValue,
    required this.time,
  });
}

class SetTrackerPage extends StatefulWidget {
  const SetTrackerPage({super.key});

  @override
  State<SetTrackerPage> createState() => _SetTrackerPageState();
}

class _SetTrackerPageState extends State<SetTrackerPage>
    with TickerProviderStateMixin {
  final PageController _themeController =
      PageController(viewportFraction: 0.28);
  final PageController _repsController =
      PageController(viewportFraction: 0.28);
  final List<_SetRecord> _records = [];

  int _themeIndex = 0;
  int _repsIndex = 4;
  bool _isRecording = false;

  late AnimationController _recordAnimController;
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _recordAnimController = AnimationController(
      vsync: this,
      duration: SetTrackerConst.buttonPressDuration,
    );
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _themeController.dispose();
    _repsController.dispose();
    _recordAnimController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  int get _todaySetCount {
    final now = DateTime.now();
    return _records
        .where((r) =>
            r.time.year == now.year &&
            r.time.month == now.month &&
            r.time.day == now.day)
        .length;
  }

  int _todayCountFor(String themeId) {
    final now = DateTime.now();
    return _records
        .where((r) =>
            r.themeId == themeId &&
            r.time.year == now.year &&
            r.time.month == now.month &&
            r.time.day == now.day)
        .length;
  }

  void _recordSet() async {
    if (_isRecording) return;
    setState(() => _isRecording = true);

    await _recordAnimController.forward();
    await _recordAnimController.reverse();

    final theme = SetTrackerConst.themes[_themeIndex];
    final reps = SetTrackerConst.repsValues[_repsIndex];

    final record = _SetRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      themeId: theme.id,
      themeLabel: theme.label,
      repsValue: reps,
      time: DateTime.now(),
    );

    setState(() {
      _records.insert(0, record);
      _isRecording = false;
    });
  }

  void _deleteRecord(String id) {
    setState(() => _records.removeWhere((r) => r.id == id));
  }

  void _clearRecords() => setState(() => _records.clear());

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HistorySheet(
        records: _records,
        onDelete: _deleteRecord,
        onClear: _clearRecords,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = SetTrackerConst.themes[_themeIndex];
    final reps = SetTrackerConst.repsValues[_repsIndex];
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final availableH = mq.size.height - mq.padding.top - mq.padding.bottom;

    // 弧线半径由屏宽决定
    final arcRadius = screenW * SetTrackerConst.arcRadiusFactor;
    // 弧线区「恰好容纳弧线 + 标签」所需高度（几何推导）：
    // 上弧圆心在区外上方(|factor|=0.95)，弧最低点 = -|factor|·H + radius，
    // 再叠加 lift(标签外推) + 标签控件余量，解得 H。
    const labelExtent = 48.0;
    final idealArcZoneH =
        (arcRadius + SetTrackerConst.topArcLift + labelExtent) /
            (1 + SetTrackerConst.topArcCenterYFactor.abs());

    // Header 高度 / 中间内容最小高度（保证记录按钮区不被压扁）
    const headerH = 64.0;
    const minMiddleH = 220.0;
    final maxArcZoneH = math.max(0.0, (availableH - headerH - minMiddleH) / 2);
    // 短屏时压缩弧线区，优先保证中间不溢出
    final arcZoneH = math.min(idealArcZoneH, maxArcZoneH);

    return Scaffold(
      backgroundColor: SetTrackerConst.bgColor,
      // 3 个彻底隔离的区域，互不重叠：顶部(Header+上弧) / 中间(信息+按钮) / 底部(下弧)
      body: SafeArea(
        child: Column(
          children: [
            // === 区域1：顶部 = Header + 上弧线 ===
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: headerH, child: _buildHeader()),
                SizedBox(
                  height: arcZoneH,
                  child: ClipRect(child: _buildTopArc()),
                ),
              ],
            ),
            // === 区域2：中间内容（填满剩余空间） ===
            Expanded(child: _buildCenterSection(theme, reps)),
            // === 区域3：底部 = 下弧线 ===
            SizedBox(
              height: arcZoneH,
              child: ClipRect(child: _buildBottomArc()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
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
                '双轮盘 · 滑动选择 · 一键记录',
                style: TextStyle(
                  fontSize: 12,
                  color: SetTrackerConst.textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
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
                child: const Icon(Icons.history,
                    color: SetTrackerConst.textPrimary, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ===== 上弧线：圆心锚在 SizedBox 顶部外侧，向下拱，半圆感 =====
  Widget _buildTopArc() {
    return LayoutBuilder(
      builder: (_, constraints) {
        final size = constraints.biggest;
        final cx = size.width / 2;
        // 圆心在区域顶部外侧：factor < 0 时圆心在区域上方
        final cy = size.height * SetTrackerConst.topArcCenterYFactor;
        final radius = size.width * SetTrackerConst.arcRadiusFactor;

        return Stack(
          children: [
            CustomPaint(
              size: size,
              painter: ArcTrackPainter(
                cx: cx,
                cy: cy,
                radius: radius,
                startAngle: SetTrackerConst.topArcStartAngle,
                sweepAngle: SetTrackerConst.topArcSweepAngle,
                selectedIndex: _themeIndex,
                itemCount: SetTrackerConst.themes.length,
                highlightColor: SetTrackerConst.themes[_themeIndex].gradient[0],
              ),
            ),
            _ArcLabelLayer(
              controller: _themeController,
              cx: cx,
              cy: cy,
              radius: radius,
              startAngle: SetTrackerConst.topArcStartAngle,
              sweepAngle: SetTrackerConst.topArcSweepAngle,
              visibleCount: SetTrackerConst.arcVisibleCount,
              lift: SetTrackerConst.topArcLift,
              items: SetTrackerConst.themes
                  .map((t) => (label: t.label, icon: t.icon, colors: t.gradient))
                  .toList(),
              selectedIndex: _themeIndex,
              glowController: _glowController,
              reverse: true,
            ),
            PageView.builder(
              controller: _themeController,
              itemCount: SetTrackerConst.themes.length,
              onPageChanged: (i) => setState(() => _themeIndex = i),
              itemBuilder: (_, __) => const SizedBox.expand(),
            ),
          ],
        );
      },
    );
  }

  // ===== 中间：信息 + 今日统计 + 记录按钮 =====
  Widget _buildCenterSection(WorkoutTheme theme, String reps) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  gradient: theme.linearGradient,
                  borderRadius: BorderRadius.circular(18),
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
                    Icon(theme.icon, color: Colors.white, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      theme.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: SetTrackerConst.shadowColor,
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.repeat, color: theme.gradient[1], size: 16),
                    const SizedBox(width: 5),
                    Text(
                      '$reps 次',
                      style: TextStyle(
                        color: theme.gradient[1],
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildTodayStatsInline(),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _recordAnimController,
            builder: (_, __) {
              final scale = 1.0 - _recordAnimController.value * 0.16;
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
                          color: theme.gradient[0].withValues(alpha: 0.45),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                        BoxShadow(
                          color: theme.gradient[1].withValues(alpha: 0.25),
                          blurRadius: 48,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add, color: Colors.white, size: 30),
                          const SizedBox(height: 2),
                          Text(
                            _isRecording ? '记录中...' : '记录',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
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
          ),
        ],
      ),
    );
  }

  Widget _buildTodayStatsInline() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: SetTrackerConst.shadowColor,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Text(
            '今日',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: SetTrackerConst.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: SetTrackerConst.themes.map((t) {
                  final count = _todayCountFor(t.id);
                  final isActive = count > 0;
                  return Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: isActive ? t.linearGradient : null,
                      color: isActive ? null : const Color(0xFFF0F0F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${t.label} $count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.normal,
                        color: isActive ? Colors.white : SetTrackerConst.textMuted,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B6B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '共 $_todaySetCount 组',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF6B6B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== 下弧线：圆心锚在 SizedBox 底部外侧，向上拱，半圆感 =====
  Widget _buildBottomArc() {
    return LayoutBuilder(
      builder: (_, constraints) {
        final size = constraints.biggest;
        final cx = size.width / 2;
        // 圆心在区域底部外侧：factor > 1 时圆心在区域下方
        final cy = size.height * SetTrackerConst.bottomArcCenterYFactor;
        final radius = size.width * SetTrackerConst.arcRadiusFactor;

        final highlightColor =
            SetTrackerConst.themes[_themeIndex].gradient[1];

        return Stack(
          children: [
            CustomPaint(
              size: size,
              painter: ArcTrackPainter(
                cx: cx,
                cy: cy,
                radius: radius,
                startAngle: SetTrackerConst.bottomArcStartAngle,
                sweepAngle: SetTrackerConst.bottomArcSweepAngle,
                selectedIndex: _repsIndex,
                itemCount: SetTrackerConst.repsValues.length,
                highlightColor: highlightColor,
              ),
            ),
            _ArcLabelLayer(
              controller: _repsController,
              cx: cx,
              cy: cy,
              radius: radius,
              startAngle: SetTrackerConst.bottomArcStartAngle,
              sweepAngle: SetTrackerConst.bottomArcSweepAngle,
              visibleCount: SetTrackerConst.arcVisibleCount,
              lift: SetTrackerConst.bottomArcLift,
              items: SetTrackerConst.repsValues
                  .map((v) => (
                        label: v,
                        icon: Icons.format_list_numbered,
                        colors: [highlightColor, highlightColor]
                      ))
                  .toList(),
              selectedIndex: _repsIndex,
              glowController: _glowController,
            ),
            PageView.builder(
              controller: _repsController,
              itemCount: SetTrackerConst.repsValues.length,
              onPageChanged: (i) => setState(() => _repsIndex = i),
              itemBuilder: (_, __) => const SizedBox.expand(),
            ),
          ],
        );
      },
    );
  }

}

// ===== 通用弧线标签层（带脉冲光晕） =====

typedef _ArcItem = ({String label, IconData icon, List<Color> colors});

class _ArcLabelLayer extends StatelessWidget {
  final PageController controller;
  final double cx;
  final double cy;
  final double radius;
  final double startAngle;
  final double sweepAngle;
  final int visibleCount;
  final double lift;
  final List<_ArcItem> items;
  final int selectedIndex;
  final AnimationController glowController;
  final bool reverse;

  const _ArcLabelLayer({
    required this.controller,
    required this.cx,
    required this.cy,
    required this.radius,
    required this.startAngle,
    required this.sweepAngle,
    required this.visibleCount,
    required this.lift,
    required this.items,
    required this.selectedIndex,
    required this.glowController,
    this.reverse = false,
  });

  @override
  Widget build(BuildContext context) {
    final k = (visibleCount - 1) / 2;

    return AnimatedBuilder(
      animation: Listenable.merge([controller, glowController]),
      builder: (_, __) {
        final t = controller.hasClients ? (controller.page ?? 0) : 0.0;
        final glowValue = glowController.value;
        final children = <Widget>[];

        for (int i = 0; i < items.length; i++) {
          final d = reverse ? t - i : i - t;
          if (d.abs() > k + 1) continue;

          final u = ((d + k) / (2 * k)).clamp(0.0, 1.0);
          final theta = startAngle + sweepAngle * u;

          final x = cx + radius * math.cos(theta);
          final y = cy + radius * math.sin(theta);

          final nx = x - cx;
          final ny = y - cy;
          final len = math.sqrt(nx * nx + ny * ny);

          // 远离圆心
          final ox = x + (nx / len) * lift;
          final oy = y + (ny / len) * lift;

          final emphasis = (1 - (d.abs() / k)).clamp(0.0, 1.0);
          final scale = 0.55 + 0.55 * emphasis;
          final opacity = 0.3 + 0.7 * emphasis;
          final item = items[i];
          final isCenter = emphasis > 0.7;

          // 脉冲光晕大小
          final glowSize = isCenter ? 16 + glowValue * 8 : 0.0;

          children.add(
            Positioned(
              left: ox - 40,
              top: oy - 30,
              width: 80,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // 脉冲光晕
                          if (isCenter)
                            Container(
                              width: 52 + glowSize,
                              height: 52 + glowSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: item.colors[0]
                                    .withValues(alpha: 0.15 * (1 - glowValue)),
                              ),
                            ),
                          // 主按钮
                          Container(
                            width: isCenter ? 52 : 40,
                            height: isCenter ? 52 : 40,
                            decoration: BoxDecoration(
                              gradient: isCenter
                                  ? LinearGradient(
                                      colors: item.colors,
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color: isCenter ? null : Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: isCenter
                                  ? [
                                      BoxShadow(
                                        color: item.colors[0]
                                            .withValues(alpha: 0.4),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.06),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                              border: isCenter
                                  ? null
                                  : Border.all(
                                      color: const Color(0xFFE8E8EC),
                                      width: 2),
                            ),
                            child: Center(
                              child: item.icon == Icons.format_list_numbered
                                  ? Text(
                                      item.label,
                                      style: TextStyle(
                                        fontSize: isCenter ? 18 : 14,
                                        fontWeight: FontWeight.bold,
                                        color: isCenter
                                            ? Colors.white
                                            : SetTrackerConst.textSecondary,
                                      ),
                                    )
                                  : Icon(
                                      item.icon,
                                      size: isCenter ? 24 : 18,
                                      color: isCenter
                                          ? Colors.white
                                          : SetTrackerConst.textSecondary,
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      if (item.icon != Icons.format_list_numbered)
                        Text(
                          item.label,
                          style: TextStyle(
                            color: isCenter
                                ? item.colors[0]
                                : SetTrackerConst.textSecondary,
                            fontSize: isCenter ? 13 : 11,
                            fontWeight: isCenter
                                ? FontWeight.bold
                                : FontWeight.w500,
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

// ===== 历史记录弹窗 =====

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
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: SetTrackerConst.bgColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
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
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: records.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fitness_center,
                            size: 56, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('还没有记录',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey.shade500)),
                        const SizedBox(height: 4),
                        Text('开始你的第一组训练吧！',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade400)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                gradient: theme.linearGradient,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Icon(theme.icon,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                            const SizedBox(width: 12),
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
                                  const SizedBox(height: 2),
                                  Text(
                                    '${record.repsValue} 次',
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
                                  child: Icon(Icons.delete_outline,
                                      size: 18, color: Colors.red),
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
