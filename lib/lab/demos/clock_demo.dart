import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lab_container.dart';
import '../models/lab_clock.dart';
import '../models/lab_clock_record.dart';
import '../providers/lab_clock_provider.dart';
import '../utils/clock_color_util.dart';

/// 时钟 Demo
class ClockDemo extends DemoPage {
  @override
  String get title => '时钟';

  @override
  String get description => '波浪分割时钟与记录';

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

class _ClockDemoPageState extends State<_ClockDemoPage> with TickerProviderStateMixin {
  // 波浪分割线位置：0.0 = 时钟全屏，1.0 = 记录全屏
  double _splitPosition = 0.50; // 默认50-50分割
  bool _isDragging = false;
  late AnimationController _animController;
  late AnimationController _snapController;
  late Animation<double> _waveAnimation;
  late Animation<double> _snapAnimation;

  // 摇一摇检测相关变量
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  double _lastAcceleration = 0;
  DateTime _lastShakeTime = DateTime.now();
  static const double _shakeThreshold = 15.0; // 摇晃阈值
  static const Duration _shakeCooldown = Duration(seconds: 2); // 摇晃冷却时间

  // 摇一摇开关状态
  bool _shakeToStartEnabled = false;

  // 吸附点位置 - 4个点：主吸附点+相邻点
  static const double _snapTop = 0.30;      // 上方相邻点（靠近1/3）
  static const double _snapBottom = 0.70;    // 下方相邻点（靠近2/3）
  static const double _snapDefault = 0.50;   // 默认中间位置

  // 吸附阈值 - 增大范围确保更容易吸附
  static const double _snapThreshold = 0.20;

  // 检测接近磁吸点的阈值（用于视觉反馈）
  static const double _snapProximityThreshold = 0.15;

  final ScrollController _clockScrollController = ScrollController();
  final ScrollController _recordScrollController = ScrollController();

  // 是否有时钟正在运行
  bool _hasRunningClock = false;

  // 当前展开的记录索引（用于点击空白处收回）
  int? _expandedRecordIndex;

  // 关闭展开的记录
  void _closeExpandedRecord() {
    if (_expandedRecordIndex != null) {
      setState(() {
        _expandedRecordIndex = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LabClockProvider>().loadClocks();
      _loadShakeState();
    });

    // 波浪动画 - 默认不循环，由时钟状态控制
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _waveAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    // 吸附动画 - 更快的吸附速度和更平滑的曲线
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),  // 从400ms减少到250ms，更灵敏
    );
    _snapAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutBack),  // 使用easeOutBack获得更有力的吸附感
    );
    _snapAnimation.addListener(() {
      if (_snapAnimation.isCompleted) {
        setState(() {});
      }
    });

    // 添加定时器检查时钟状态，控制波浪动画
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final provider = context.read<LabClockProvider>();
      final hasRunning = provider.clocks.any((c) => c.isRunning);

      if (hasRunning != _hasRunningClock) {
        setState(() {
          _hasRunningClock = hasRunning;
        });
      }

      if (hasRunning && !_animController.isAnimating) {
        _animController.repeat();
      } else if (!hasRunning && _animController.isAnimating) {
        _animController.stop();
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _snapController.dispose();
    _clockScrollController.dispose();
    _recordScrollController.dispose();
    _accelerometerSubscription?.cancel();
    super.dispose();
  }

  // 切换摇一摇启动功能（带权限申请）
  Future<void> _toggleShakeToStart() async {
    if (_shakeToStartEnabled) {
      // 关闭摇一摇
      setState(() {
        _shakeToStartEnabled = false;
      });
      _accelerometerSubscription?.cancel();
      _accelerometerSubscription = null;
      await _saveShakeState(false);
    } else {
      // 开启摇一摇 - 申请权限（通过震动反馈确认）
      // 震动需要 VIBRATE 权限（已在 AndroidManifest 中配置）
      await HapticFeedback.mediumImpact();
      setState(() {
        _shakeToStartEnabled = true;
      });
      _startAccelerometerListening();
      await _saveShakeState(true);
    }
  }

  // 加载保存的摇一摇状态
  Future<void> _loadShakeState() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('shake_to_start_enabled') ?? false;
    if (enabled && mounted) {
      setState(() {
        _shakeToStartEnabled = true;
      });
      _startAccelerometerListening();
    }
  }

  // 保存摇一摇状态
  Future<void> _saveShakeState(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shake_to_start_enabled', enabled);
  }

  // 开始监听加速度传感器
  void _startAccelerometerListening() {
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      _detectShake(event);
    });
  }

  // 检测摇晃动作
  void _detectShake(AccelerometerEvent event) {
    // 计算加速度向量的大小（去除重力影响）
    final double acceleration = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z
    );

    // 减去重力加速度 (~9.8)
    final double netAcceleration = (acceleration - 9.8).abs();

    // 检测摇晃
    if (netAcceleration > _shakeThreshold) {
      final now = DateTime.now();
      // 检查冷却时间
      if (now.difference(_lastShakeTime) > _shakeCooldown) {
        _lastShakeTime = now;
        _onShakeDetected();
      }
    }

    _lastAcceleration = acceleration;
  }

  // 摇晃检测到后的回调
  void _onShakeDetected() {
    if (!mounted) return;

    // 震动反馈
    HapticFeedback.mediumImpact();

    // 查找第一个未运行的时钟并启动
    final provider = context.read<LabClockProvider>();
    final clocks = provider.clocks;

    // 找到第一个未运行的时钟
    final firstStoppedClock = clocks.where((c) => !c.isRunning).firstOrNull;

    if (firstStoppedClock != null) {
      provider.startCountdown(firstStoppedClock.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('摇一摇启动: ${firstStoppedClock.title}'),
            backgroundColor: const Color(0xFF007AFF),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('没有可启动的时钟'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  // 检查是否接近磁吸点
  (bool isNear, int? snapPointIndex) _checkSnapProximity(double position) {
    final points = [_snapTop, _snapBottom, _snapDefault];
    for (int i = 0; i < points.length; i++) {
      if ((position - points[i]).abs() <= _snapProximityThreshold) {
        return (true, i);
      }
    }
    return (false, null);
  }

  // 执行吸附动画 - 找到最近的吸附点
  void _snapToNearest(double fromPosition) {
    final points = [_snapTop, _snapBottom, _snapDefault];

    // 找到最近的吸附点
    double nearest = fromPosition;
    double minDistance = double.infinity;

    for (final point in points) {
      final distance = (fromPosition - point).abs();
      if (distance < minDistance) {
        minDistance = distance;
        nearest = point;
      }
    }

    // 只有在阈值范围内才吸附
    if (minDistance <= _snapThreshold) {
      _animateSnap(fromPosition, nearest);
    }
  }

  // 吸附动画
  void _animateSnap(double from, double to) {
    final startPosition = from;
    final targetPosition = to;

    _snapController.reset();
    _snapController.forward();

    _snapAnimation.addListener(() {
      if (_snapAnimation.status == AnimationStatus.forward) {
        setState(() {
          _splitPosition = startPosition + (targetPosition - startPosition) * _snapAnimation.value;
        });
      }
    });

    _snapController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _snapController.removeStatusListener((_) {});
        setState(() {
          _splitPosition = targetPosition;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final splitY = screenHeight * (1 - _splitPosition);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          '摇一摇启动',
          style: TextStyle(
            color: Color(0xFF000000),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          Switch(
            value: _shakeToStartEnabled,
            onChanged: (_) => _toggleShakeToStart(),
            activeColor: const Color(0xFF007AFF),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _closeExpandedRecord, // 点击屏幕任何位置收回
          child: Stack(
          children: [
          // 时钟页面（上半部分）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: splitY,
            child: _buildClockPage(context),
          ),
          // 记录页面（下半部分）- 波浪线作为其顶部
          Positioned(
            top: splitY,
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              children: [
                // 波浪分割线 - 位于记录页面顶部
                GestureDetector(
                  onVerticalDragStart: (_) {
                    setState(() => _isDragging = true);
                  },
                  onVerticalDragUpdate: (details) {
                    setState(() {
                      // 向上拖动增加splitPosition（让clock区域变大），向下拖动减小
                      final deltaRatio = details.delta.dy / screenHeight;
                      _splitPosition = (_splitPosition - deltaRatio).clamp(0.1, 0.9);
                    });
                  },
                  onVerticalDragEnd: (_) {
                    setState(() => _isDragging = false);
                    _snapToNearest(_splitPosition);
                  },
                  child: Container(
                    height: 50, // 拖动响应区域
                    color: Colors.transparent,
                    child: Stack(
                      children: [
                        // 波浪线
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 20,
                          child: Builder(
                            builder: (context) {
                              // 检查是否接近磁吸点，用于增强视觉效果
                              final proximity = _checkSnapProximity(_splitPosition);

                              return _BreathingWaveLine(
                                isRunning: _hasRunningClock,
                                isDragging: _isDragging,
                                color: const Color(0xFF007AFF),
                                isNearSnapPoint: proximity.$1,
                                snapPointIndex: proximity.$2,
                              );
                            },
                          ),
                        ),
                        // iOS 26风格手柄 - 极简
                        Positioned(
                          top: 4,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                              width: _isDragging ? 44 : 36,
                              height: _isDragging ? 5 : 4,
                              decoration: BoxDecoration(
                                color: const Color(0xFFC7C7CC),
                                borderRadius: BorderRadius.circular(2.5),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 记录内容区域
                Expanded(
                  child: _buildRecordPageContent(context),
                ),
              ],
            ),
          ),
          // 顶部提示 - 只在接近时钟全屏时显示
          if (_splitPosition < 0.25)
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _splitPosition < 0.2 ? 0.6 : 0.0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '向下拖动波浪线查看记录',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
      ),
      floatingActionButton: _buildFloatingActionButton(context),
    );
  }

  Widget _buildClockPage(BuildContext context) {
    return Consumer<LabClockProvider>(
      builder: (context, provider, child) {
        if (provider.clocks.isEmpty) {
          return _buildEmpty(context);
        }
        return Container(
          color: Colors.white,
          child: GridView.builder(
            controller: _clockScrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.0,
            ),
            itemCount: provider.clocks.length,
            itemBuilder: (context, index) {
              final clock = provider.clocks[index];
              return _ClockCard(
                clock: clock,
                onTap: () => _editClock(context, clock),
                onDelete: () => _deleteClock(context, clock),
                onStart: () => context.read<LabClockProvider>().startCountdown(clock.id),
                onPause: () => context.read<LabClockProvider>().pauseCountdown(clock.id),
                onReset: () => context.read<LabClockProvider>().resetCountdown(clock.id),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildRecordPageContent(BuildContext context) {
    return Consumer<LabClockProvider>(
      builder: (context, provider, child) {
        final records = provider.records;
        return Container(
          color: Colors.white,
          child: Column(
            children: [
              // 记录标题栏
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      color: const Color(0xFF007AFF),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      '使用记录',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF000000),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Spacer(),
                    if (records.isNotEmpty)
                      GestureDetector(
                        onTap: () => _showClearRecordsDialog(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            '清空',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE5E5EA)),
              Expanded(
                child: records.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history_toggle_off_rounded,
                              size: 56,
                              color: const Color(0xFFE5E5EA),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '暂无记录',
                              style: TextStyle(
                                fontSize: 15,
                                color: Color(0xFF8E8E93),
                              ),
                            ),
                          ],
                        ),
                      )
                    : GestureDetector(
                        onTap: _closeExpandedRecord, // 点击空白处收回
                        child: ListView.builder(
                          controller: _recordScrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: records.length,
                          itemBuilder: (_, index) => _buildModernRecordItem(context, records[index], index),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFloatingActionButton(BuildContext context) {
    final themeColor = Theme.of(context).primaryColor;
    return FloatingActionButton(
      onPressed: () => _addClock(context),
      backgroundColor: themeColor,
      child: const Icon(Icons.add, color: Colors.white),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_outlined, size: 64, color: const Color(0xFFE5E5EA)),
            const SizedBox(height: 16),
            Text('暂无时钟', style: TextStyle(color: const Color(0xFF8E8E93))),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _addClock(context),
              icon: const Icon(Icons.add),
              label: const Text('添加时钟'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernRecordItem(BuildContext context, LabClockRecord record, int index) {
    final dateFormat = DateFormat('MM-dd HH:mm');

    // 直接使用 provider 提供的统一方法计算实时时间
    final provider = context.read<LabClockProvider>();
    final liveDuration = provider.getRecordLiveDuration(record);
    final durationStr = _formatDuration(liveDuration);

    // 计算实际使用时间
    final actualDuration = provider.getRecordLiveDuration(record);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0x0D000000),
              offset: const Offset(0, 1),
              blurRadius: 4,
            ),
          ],
        ),
        child: _RecordSwipeAction(
          onCreate: () async {
            // 优先使用自定义名称，否则使用原始名称
            final title = record.customTitle ?? record.clockTitle;
            if (actualDuration > 0) {
              await context.read<LabClockProvider>().createClock(
                title: title,
                durationSeconds: actualDuration,
                color: '#007AFF',
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已创建新时钟: $durationStr'),
                    backgroundColor: const Color(0xFF007AFF),
                  ),
                );
              }
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('记录时间无效'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            }
          },
          onDelete: () {
            context.read<LabClockProvider>().deleteRecord(record.id);
          },
          index: index,
          onExpand: () {
            setState(() {
              _expandedRecordIndex = index;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: record.completed
                      ? const Color(0xFF34C759).withOpacity(0.1)
                      : const Color(0xFFFF9500).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  record.completed ? Icons.check_rounded : Icons.schedule_rounded,
                  color: record.completed ? const Color(0xFF34C759) : const Color(0xFFFF9500),
                  size: 22,
                ),
              ),
              title: GestureDetector(
                onLongPress: () => _showEditRecordTitleDialog(context, record),
                child: Text(
                  record.customTitle ?? record.clockTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF000000),
                  ),
                ),
              ),
              subtitle: Text(
                '${dateFormat.format(record.startTime)} • 计划: ${_formatDuration(record.durationSeconds)}',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF8E8E93),
                ),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: record.completed
                      ? const Color(0xFF34C759).withOpacity(0.1)
                      : const Color(0xFFFF9500).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '实际: $durationStr',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: record.completed ? const Color(0xFF34C759) : const Color(0xFFFF9500),
                  ),
                ),
              ),
            ),
          ),
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

  void _showEditRecordTitleDialog(BuildContext context, LabClockRecord record) {
    final controller = TextEditingController(text: record.customTitle ?? record.clockTitle);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '记录名称',
            hintText: '输入自定义名称',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                context.read<LabClockProvider>().updateRecordTitle(record.id, newTitle);
              }
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showClearRecordsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空记录'),
        content: const Text('确定清空所有使用记录吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              context.read<LabClockProvider>().clearRecords();
              Navigator.pop(ctx);
            },
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h}小时${m}分';
    } else if (m > 0) {
      return '${m}分${s}秒';
    } else {
      return '${s}秒';
    }
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(clock == null ? '添加时钟' : '编辑时钟', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, size: 24),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: '标题', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: '描述', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              const Text('倒计时时长:', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _timePicker('时', hours, 23, (v) => setState(() => hours = v)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(':', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                  _timePicker('分', minutes, 59, (v) => setState(() => minutes = v)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(':', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                  _timePicker('秒', seconds, 59, (v) => setState(() => seconds = v)),
                ],
              ),
              const SizedBox(height: 16),
              const Text('颜色:', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Center(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: colors.map((c) {
                    final isSelected = c == selectedColor;
                    return GestureDetector(
                      onTap: () => setState(() => selectedColor = c),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(int.parse(c.replaceFirst('#', '0xFF'))),
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Colors.black, width: 3)
                              : null,
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(clock == null ? '添加' : '保存', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          width: 60,
          child: ListWheelScrollView.useDelegate(
            itemExtent: 40,
            perspective: 0.005,
            diameterRatio: 1.5,
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
                      fontSize: isSelected ? 24 : 16,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.black : const Color(0xFFC7C7CC),
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

/// 波浪线画笔
class _WaveLinePainter extends CustomPainter {
  final double waveAnimation;
  final bool isDragging;
  final Color color;
  final bool isNearSnapPoint;  // 是否接近磁吸点
  final int? snapPointIndex;   // 磁吸点索引 (0=1/3, 1=2/3)

  _WaveLinePainter({
    required this.waveAnimation,
    required this.isDragging,
    required this.color,
    this.isNearSnapPoint = false,
    this.snapPointIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 根据是否接近磁吸点调整样式
    final isNear = isNearSnapPoint || isDragging;
    final opacity = isNear ? 0.8 : 0.4;
    final strokeWidth = isNear ? 3.5 : 2.0;

    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    // 增强波浪效果 - 接近磁吸点时波浪更大
    final baseWaveHeight = isDragging ? 12.0 : 8.0;
    final waveHeight = isNearSnapPoint ? baseWaveHeight * 1.5 : baseWaveHeight;

    path.moveTo(0, size.height / 2);

    for (double x = 0; x <= size.width; x += 5) {
      final normalizedX = x / size.width;
      final wavePhase = waveAnimation + (normalizedX * 4 * math.pi);
      final yOffset = math.sin(wavePhase) * waveHeight;

      // 在1/3和2/3位置添加增强的磁吸点效果
      final snapEffect = _getSnapEffect(normalizedX);
      final snapAmplitude = isNearSnapPoint ? 10.0 : 6.0;  // 接近时振幅更大
      final snapYOffset = snapEffect * math.sin(waveAnimation * 2) * snapAmplitude;

      // 如果接近特定磁吸点，在该位置产生脉冲效果
      double pulseOffset = 0;
      if (isNearSnapPoint && snapPointIndex != null) {
        final targetX = snapPointIndex == 0 ? 1.0 / 3.0 : 2.0 / 3.0;
        final distToTarget = (normalizedX - targetX).abs();
        if (distToTarget < 0.15) {
          // 在磁吸点附近产生脉冲
          final pulseIntensity = 1.0 - (distToTarget / 0.15);
          pulseOffset = math.sin(waveAnimation * 3) * 4 * pulseIntensity;
        }
      }

      path.lineTo(x, size.height / 2 + yOffset + snapYOffset + pulseOffset);
    }

    canvas.drawPath(path, paint);
  }

  double _getSnapEffect(double normalizedX) {
    // 在1/3和2/3位置有更强的波浪效果
    const snapOneThird = 1.0 / 3.0;
    const snapTwoThird = 2.0 / 3.0;

    final distToFirst = (normalizedX - snapOneThird).abs();
    final distToSecond = (normalizedX - snapTwoThird).abs();

    // 增加影响范围从0.1到0.15
    if (distToFirst < 0.15) {
      return (1.0 - distToFirst / 0.15);
    } else if (distToSecond < 0.15) {
      return (1.0 - distToSecond / 0.15);
    }
    return 0.0;
  }

  @override
  bool shouldRepaint(_WaveLinePainter oldDelegate) {
    return waveAnimation != oldDelegate.waveAnimation ||
        isDragging != oldDelegate.isDragging ||
        color != oldDelegate.color ||
        isNearSnapPoint != oldDelegate.isNearSnapPoint ||
        snapPointIndex != oldDelegate.snapPointIndex;
  }
}

/// 呼吸波浪线条组件
/// - 运行时：显示波浪动画，带呼吸效果
/// - 停止时：渐变为直线
class _BreathingWaveLine extends StatefulWidget {
  final bool isRunning;
  final bool isDragging;
  final Color color;
  final bool isNearSnapPoint;
  final int? snapPointIndex;

  const _BreathingWaveLine({
    required this.isRunning,
    required this.isDragging,
    required this.color,
    this.isNearSnapPoint = false,
    this.snapPointIndex,
  });

  @override
  State<_BreathingWaveLine> createState() => _BreathingWaveLineState();
}

class _BreathingWaveLineState extends State<_BreathingWaveLine>
    with TickerProviderStateMixin {
  late AnimationController _waveController;   // 波浪动画
  late AnimationController _breathController; // 呼吸动画
  late AnimationController _fadeController;   // 渐变到直线的动画

  late Animation<double> _waveAnimation;
  late Animation<double> _breathAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // 波浪动画控制器
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _waveAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _waveController, curve: Curves.linear),
    );

    // 呼吸动画控制器 - 控制波浪幅度周期变化
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _breathAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );

    // 渐变动画控制器 - 停止时波浪平滑过渡到直线
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    // 根据运行状态启动/停止动画
    _updateAnimationState();
  }

  void _updateAnimationState() {
    if (widget.isRunning) {
      // 运行时：启动波浪和呼吸动画
      _waveController.repeat();
      _breathController.repeat(reverse: true);
      // 如果之前是停止状态，平滑过渡
      if (_fadeController.value > 0) {
        _fadeController.reverse();
      }
    } else {
      // 停止时：停止波浪动画
      _waveController.stop();
      _breathController.stop();
      // 渐变到直线
      if (_fadeController.value < 1) {
        _fadeController.forward();
      }
    }
  }

  @override
  void didUpdateWidget(_BreathingWaveLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRunning != oldWidget.isRunning) {
      _updateAnimationState();
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _breathController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_waveAnimation, _breathAnimation, _fadeAnimation]),
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _BreathingWavePainter(
            wavePhase: _waveAnimation.value,
            breathIntensity: _breathAnimation.value,
            fadeProgress: _fadeAnimation.value,
            isDragging: widget.isDragging,
            color: widget.color,
            isNearSnapPoint: widget.isNearSnapPoint,
            snapPointIndex: widget.snapPointIndex,
          ),
        );
      },
    );
  }
}

/// 呼吸波浪线画笔
class _BreathingWavePainter extends CustomPainter {
  final double wavePhase;        // 波浪相位
  final double breathIntensity;  // 呼吸强度 (0.6-1.0)
  final double fadeProgress;     // 渐变进度 (1.0=波浪, 0.0=直线)
  final bool isDragging;
  final Color color;
  final bool isNearSnapPoint;
  final int? snapPointIndex;

  _BreathingWavePainter({
    required this.wavePhase,
    required this.breathIntensity,
    required this.fadeProgress,
    required this.isDragging,
    required this.color,
    this.isNearSnapPoint = false,
    this.snapPointIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 计算透明度：渐变过程中透明度降低
    final baseOpacity = isDragging ? 0.8 : 0.5;
    final opacity = baseOpacity * fadeProgress + 0.3 * (1 - fadeProgress);

    final isNear = isNearSnapPoint || isDragging;
    final strokeWidth = isNear ? 3.0 : 2.0;

    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    // 基础波浪高度，受呼吸效果影响
    final baseWaveHeight = isDragging ? 12.0 : 8.0;
    final waveHeight = baseWaveHeight * breathIntensity;
    final nearWaveHeight = waveHeight * 1.5;

    path.moveTo(0, size.height / 2);

    for (double x = 0; x <= size.width; x += 5) {
      final normalizedX = x / size.width;

      // 基础波浪
      final waveOffset = math.sin(wavePhase + normalizedX * 4 * math.pi) * waveHeight;

      // 磁吸点增强效果
      final snapEffect = _getSnapEffect(normalizedX);
      final snapOffset = snapEffect * math.sin(wavePhase * 2) * nearWaveHeight * 0.6;

      // 脉冲效果
      double pulseOffset = 0;
      if (isNearSnapPoint && snapPointIndex != null) {
        final targetX = snapPointIndex == 0 ? 1.0 / 3.0 : 2.0 / 3.0;
        final distToTarget = (normalizedX - targetX).abs();
        if (distToTarget < 0.15) {
          final pulseIntensity = (1 - distToTarget / 0.15) * breathIntensity;
          pulseOffset = math.sin(wavePhase * 3) * 5 * pulseIntensity;
        }
      }

      // 计算最终y坐标（混合波浪和直线）
      final waveY = size.height / 2 + waveOffset + snapOffset + pulseOffset;
      final straightY = size.height / 2;
      final y = straightY + (waveY - straightY) * fadeProgress;

      path.lineTo(x, y);
    }

    canvas.drawPath(path, paint);
  }

  double _getSnapEffect(double normalizedX) {
    const snapOneThird = 1.0 / 3.0;
    const snapTwoThird = 2.0 / 3.0;
    const threshold = 0.15;

    final distToFirst = (normalizedX - snapOneThird).abs();
    final distToSecond = (normalizedX - snapTwoThird).abs();

    if (distToFirst < threshold) {
      return 1.0 - distToFirst / threshold;
    } else if (distToSecond < threshold) {
      return 1.0 - distToSecond / threshold;
    }
    return 0.0;
  }

  @override
  bool shouldRepaint(_BreathingWavePainter oldDelegate) {
    return wavePhase != oldDelegate.wavePhase ||
        breathIntensity != oldDelegate.breathIntensity ||
        fadeProgress != oldDelegate.fadeProgress ||
        isDragging != oldDelegate.isDragging ||
        isNearSnapPoint != oldDelegate.isNearSnapPoint ||
        snapPointIndex != oldDelegate.snapPointIndex;
  }
}

/// 记录项滑动操作组件（类似QQ滑动效果）
class _RecordSwipeAction extends StatefulWidget {
  final Widget child;
  final VoidCallback onCreate;
  final VoidCallback onDelete;
  final int index;
  final VoidCallback onExpand; // 展开时回调，用于点击空白处收回

  const _RecordSwipeAction({
    super.key,
    required this.child,
    required this.onCreate,
    required this.onDelete,
    required this.index,
    required this.onExpand,
  });

  @override
  State<_RecordSwipeAction> createState() => _RecordSwipeActionState();
}

class _RecordSwipeActionState extends State<_RecordSwipeAction> {
  double _offsetX = 0;
  static const double _actionWidth = 80;
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _offsetX += details.delta.dx;
          _offsetX = _offsetX.clamp(-_actionWidth * 2, 0);
        });
      },
      onHorizontalDragEnd: (details) {
        if (_offsetX < -_actionWidth * 0.4) {
          setState(() {
            _offsetX = -_actionWidth * 2;
            _isExpanded = true;
          });
          widget.onExpand(); // 通知父组件展开
        } else {
          setState(() {
            _offsetX = 0;
            _isExpanded = false;
          });
        }
      },
      onTap: () {
        // 点击内容区域，如果已展开则收起
        if (_isExpanded) {
          setState(() {
            _offsetX = 0;
            _isExpanded = false;
          });
        }
      },
      child: SizedBox(
        height: 70,
        child: Stack(
          children: [
            // 空白区域点击收回
            if (_isExpanded)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _offsetX = 0;
                      _isExpanded = false;
                    });
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),
            // 按钮层（溢出在右侧）
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _actionWidth * 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // 删除按钮
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _offsetX = 0;
                        _isExpanded = false;
                      });
                      widget.onDelete();
                    },
                    child: Container(
                      width: _actionWidth,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF3B30),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete, color: Colors.white, size: 24),
                          SizedBox(height: 4),
                          Text('删除', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  // 创建按钮
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _offsetX = 0;
                        _isExpanded = false;
                      });
                      widget.onCreate();
                    },
                    child: Container(
                      width: _actionWidth,
                      decoration: const BoxDecoration(
                        color: Color(0xFF007AFF),
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: Colors.white, size: 24),
                          SizedBox(height: 4),
                          Text('创建', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 内容层（随手势移动）
            Transform.translate(
              offset: Offset(_offsetX, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 时钟卡片
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
    final baseColor = Color(int.parse(clock.color?.replaceFirst('#', '0xFF') ?? '0xFF2196F3'));

    // 使用颜色工具类计算动态颜色
    final clockColor = ClockColorUtil.getClockColor(
      baseColor: baseColor,
      remainingSeconds: clock.remainingSeconds,
      durationSeconds: clock.durationSeconds ?? 0,
      maxDarkness: 0.75,
      curve: ClockColorUtil.curves['easeInQuad'],
    );

    final bgColor = ClockColorUtil.getBackgroundColor(
      baseColor: baseColor,
      remainingSeconds: clock.remainingSeconds,
      durationSeconds: clock.durationSeconds ?? 0,
    );

    final borderColor = ClockColorUtil.getBorderColor(
      baseColor: baseColor,
      remainingSeconds: clock.remainingSeconds,
      durationSeconds: clock.durationSeconds ?? 0,
    );

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Expanded(
                    child: Text(
                      clock.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF000000),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: clockColor.withOpacity(0.6),
                      ),
                    ),
                  ),
                ],
              ),
              // 描述
              if (clock.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    clock.description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8E8E93),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const Spacer(),
              // 时间显示
              Center(
                child: Text(
                  _formatTime(clock.remainingSeconds),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: clockColor,
                    letterSpacing: -1,
                  ),
                ),
              ),
              const Spacer(),
              // 控制按钮
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ControlButton(
                      icon: clock.isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: clockColor,
                      onTap: clock.isRunning ? onPause : onStart,
                    ),
                    const SizedBox(width: 12),
                    _ControlButton(
                      icon: Icons.refresh_rounded,
                      color: const Color(0xFF8E8E93),
                      onTap: onReset,
                    ),
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
    final isNegative = seconds < 0;
    final absSeconds = seconds.abs();
    final h = absSeconds ~/ 3600;
    final m = (absSeconds % 3600) ~/ 60;
    final s = absSeconds % 60;
    final sign = isNegative ? '-' : '';
    return '$sign${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}

void registerClockDemo() {
  demoRegistry.register(ClockDemo());
}
