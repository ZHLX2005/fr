import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../lab_container.dart';

/// 传感器 Demo - 实时数值可视化
class SensorDemo extends DemoPage {
  @override
  String get title => '传感器';

  @override
  String get description => '陀螺仪/加速度计/磁力计实时数值可视化';

  @override
  bool get preferFullScreen => false;

  @override
  Widget buildPage(BuildContext context) {
    return const _SensorPage();
  }
}

class _SensorPage extends StatefulWidget {
  const _SensorPage();

  @override
  State<_SensorPage> createState() => _SensorPageState();
}

class _SensorPageState extends State<_SensorPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 传感器流
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  StreamSubscription<MagnetometerEvent>? _magSubscription;
  StreamSubscription<UserAccelerometerEvent>? _userAccelSubscription;

  // 当前数值
  double _accelX = 0, _accelY = 0, _accelZ = 0;
  double _gyroX = 0, _gyroY = 0, _gyroZ = 0;
  double _magX = 0, _magY = 0, _magZ = 0;
  double _userAccelX = 0, _userAccelY = 0, _userAccelZ = 0;

  // 历史数据（用于波形图）
  final List<double> _accelHistoryX = [];
  final List<double> _accelHistoryY = [];
  final List<double> _accelHistoryZ = [];
  static const int _historyMax = 60;

  // 传感器可用性
  bool _accelAvailable = false;
  bool _gyroAvailable = false;
  bool _magAvailable = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initSensors();
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    _tabController.dispose();
    super.dispose();
  }

  void _cancelSubscriptions() {
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
    _magSubscription?.cancel();
    _userAccelSubscription?.cancel();
  }

  void _initSensors() {
    // 加速度计
    _accelSubscription = accelerometerEventStream().listen(
      (event) {
        setState(() {
          _accelX = event.x;
          _accelY = event.y;
          _accelZ = event.z;
          _accelAvailable = true;
          _updateHistory(_accelHistoryX, event.x);
          _updateHistory(_accelHistoryY, event.y);
          _updateHistory(_accelHistoryZ, event.z);
        });
      },
      onError: (e) {
        setState(() => _accelAvailable = false);
      },
    );

    // 陀螺仪
    _gyroSubscription = gyroscopeEventStream().listen(
      (event) {
        setState(() {
          _gyroX = event.x;
          _gyroY = event.y;
          _gyroZ = event.z;
          _gyroAvailable = true;
        });
      },
      onError: (e) {
        setState(() => _gyroAvailable = false);
      },
    );

    // 磁力计
    _magSubscription = magnetometerEventStream().listen(
      (event) {
        setState(() {
          _magX = event.x;
          _magY = event.y;
          _magZ = event.z;
          _magAvailable = true;
        });
      },
      onError: (e) {
        setState(() => _magAvailable = false);
      },
    );

    // 用户加速度（去除重力）
    _userAccelSubscription = userAccelerometerEventStream().listen((event) {
      setState(() {
        _userAccelX = event.x;
        _userAccelY = event.y;
        _userAccelZ = event.z;
      });
    }, onError: (e) {});
  }

  void _updateHistory(List<double> history, double value) {
    history.add(value);
    if (history.length > _historyMax) {
      history.removeAt(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      body: SafeArea(
        child: Column(
          children: [
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAccelerometerTab(),
                  _buildGyroscopeTab(),
                  _buildMagnetometerTab(),
                  _buildUserAccelerometerTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: const Color(0xFF0A84FF),
          borderRadius: BorderRadius.circular(8),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF8E8E93),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'ACC'),
          Tab(text: 'GYRO'),
          Tab(text: 'MAG'),
          Tab(text: 'USER'),
        ],
      ),
    );
  }

  Widget _buildAccelerometerTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSensorInfo(
            '加速度计 (Accelerometer)',
            '含重力影响，单位 m/s²',
            _accelAvailable,
          ),
          const SizedBox(height: 16),
          _buildWaveChart('X', _accelHistoryX, Colors.red),
          _buildWaveChart('Y', _accelHistoryY, Colors.green),
          _buildWaveChart('Z', _accelHistoryZ, Colors.blue),
          const SizedBox(height: 16),
          _buildValueCard('X', _accelX),
          _buildValueCard('Y', _accelY),
          _buildValueCard('Z', _accelZ),
          const SizedBox(height: 12),
          _buildMagnitudeCard(),
        ],
      ),
    );
  }

  Widget _buildGyroscopeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSensorInfo('陀螺仪 (Gyroscope)', '角速度，单位 rad/s', _gyroAvailable),
          const SizedBox(height: 16),
          _buildValueCard('X', _gyroX, precision: 4),
          _buildValueCard('Y', _gyroY, precision: 4),
          _buildValueCard('Z', _gyroZ, precision: 4),
          const SizedBox(height: 16),
          _buildDescriptionCard(
            '典型值参考',
            '静止: ≈ 0\n缓慢旋转: 0.1 - 0.5\n快速旋转: 1.0 - 5.0',
          ),
        ],
      ),
    );
  }

  Widget _buildMagnetometerTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSensorInfo('磁力计 (Magnetometer)', '磁场强度，单位 μT', _magAvailable),
          const SizedBox(height: 16),
          _buildValueCard('X', _magX),
          _buildValueCard('Y', _magY),
          _buildValueCard('Z', _magZ),
          const SizedBox(height: 16),
          _buildDescriptionCard(
            '典型值参考',
            '地球磁场水平分量: 20-40 μT\n地磁总场强: 40-60 μT\n手机附近磁场扰动: > 100 μT',
          ),
        ],
      ),
    );
  }

  Widget _buildUserAccelerometerTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSensorInfo(
            '用户加速度 (User Accelerometer)',
            '去除重力后的加速度，单位 m/s²',
            true,
          ),
          const SizedBox(height: 16),
          _buildValueCard('X', _userAccelX),
          _buildValueCard('Y', _userAccelY),
          _buildValueCard('Z', _userAccelZ),
          const SizedBox(height: 16),
          _buildDescriptionCard(
            '说明',
            '去除了重力加速度分量\n通常用于检测手势、摇晃等用户动作\n静止时理论上接近 (0, 0, 0)',
          ),
        ],
      ),
    );
  }

  Widget _buildSensorInfo(String title, String subtitle, bool available) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            available ? Icons.sensors : Icons.sensors_off,
            color: available
                ? const Color(0xFF30D158)
                : const Color(0xFFFF453A),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: available
                  ? const Color(0xFF30D158).withValues(alpha: 0.2)
                  : const Color(0xFFFF453A).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              available ? '可用' : '不可用',
              style: TextStyle(
                color: available
                    ? const Color(0xFF30D158)
                    : const Color(0xFFFF453A),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValueCard(String axis, double value, {int precision = 2}) {
    final isPositive = value >= 0;
    final absValue = value.abs();
    final color = axis == 'X'
        ? Colors.red
        : axis == 'Y'
        ? Colors.green
        : Colors.blue;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                axis,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isPositive ? '+' : '-'}${absValue.toStringAsFixed(precision)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMagnitudeCard() {
    final magnitude = _accelX * _accelX + _accelY * _accelY + _accelZ * _accelZ;
    final sqrtMag = magnitude > 0 ? _sqrtApprox(magnitude) : 0.0;
    // 静止时约等于重力加速度 9.8
    final deviation = (sqrtMag - 9.8).abs();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF0A84FF).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          const Text(
            '向量模长 (|a|)',
            style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            sqrtMag.toStringAsFixed(3),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '与重力加速度偏差: ${deviation.toStringAsFixed(3)} m/s²',
            style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveChart(String label, List<double> history, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                history.isNotEmpty ? history.last.toStringAsFixed(2) : '0.00',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 30,
            child: CustomPaint(
              size: const Size(double.infinity, 30),
              painter: _WavePainter(history, color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionCard(String title, String content) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0A84FF),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  double _sqrtApprox(double x) {
    // 牛顿法近似开方
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
}

/// 波形绘制器
class _WavePainter extends CustomPainter {
  final List<double> history;
  final Color color;

  _WavePainter(this.history, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final maxVal = history.map((e) => e.abs()).reduce((a, b) => a > b ? a : b);
    final scale = maxVal > 0 ? size.height / 2 / maxVal : 1.0;
    final centerY = size.height / 2;

    for (int i = 0; i < history.length; i++) {
      final x = i * size.width / (history.length - 1);
      final y = centerY - history[i] * scale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.history != history;
  }
}

void registerSensorDemo() {
  demoRegistry.register(SensorDemo());
}
