import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:torch_light/torch_light.dart';
import 'package:permission_handler/permission_handler.dart';
import '../lab_container.dart';

/// 手电筒 Demo
class TorchDemo extends DemoPage {
  @override
  String get title => '手电筒';

  @override
  String get description => '手电筒和全白屏幕照亮功能';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const _TorchPage();
  }
}

class _TorchPage extends StatefulWidget {
  const _TorchPage();

  @override
  State<_TorchPage> createState() => _TorchPageState();
}

class _TorchPageState extends State<_TorchPage> with SingleTickerProviderStateMixin {
  // 手电筒状态
  bool _isTorchOn = false;
  bool _torchAvailable = false;

  // 打光灯状态
  bool _isFloodLightOn = false;
  double _floodLightBrightness = 1.0;

  // 模式：torch-手电筒 / floodlight-打光灯
  int _currentMode = 0; // 0: 手电筒, 1: 打光灯

  // 全屏打光灯覆盖层
  bool _showFloodLightOverlay = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _checkTorchAvailability();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _turnOffTorch();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkTorchAvailability() async {
    try {
      final isAvailable = await TorchLight.isTorchAvailable();
      setState(() {
        _torchAvailable = isAvailable;
      });
    } catch (e) {
      setState(() {
        _torchAvailable = false;
      });
    }
  }

  Future<void> _toggleTorch() async {
    if (!_torchAvailable) {
      _showPermissionDialog();
      return;
    }

    try {
      if (_isTorchOn) {
        await TorchLight.disableTorch();
        _pulseController.stop();
      } else {
        // 请求相机权限
        final status = await Permission.camera.request();
        if (status.isGranted) {
          await TorchLight.enableTorch();
          _pulseController.repeat(reverse: true);
        } else {
          _showPermissionDialog();
          return;
        }
      }
      setState(() {
        _isTorchOn = !_isTorchOn;
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('Torch error: $e');
    }
  }

  Future<void> _turnOffTorch() async {
    if (_isTorchOn) {
      try {
        await TorchLight.disableTorch();
        _pulseController.stop();
        setState(() {
          _isTorchOn = false;
        });
      } catch (e) {
        debugPrint('Turn off torch error: $e');
      }
    }
  }

  void _toggleFloodLight() {
    setState(() {
      _isFloodLightOn = !_isFloodLightOn;
      _showFloodLightOverlay = _isFloodLightOn;
    });
    HapticFeedback.mediumImpact();
  }

  void _setFloodLightBrightness(double value) {
    setState(() {
      _floodLightBrightness = value;
    });
  }

  void _closeFloodLight() {
    setState(() {
      _isFloodLightOn = false;
      _showFloodLightOverlay = false;
    });
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('权限申请'),
        content: const Text('手电筒功能需要相机权限，请前往设置开启。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      body: Stack(
        children: [
          // 主内容
          SafeArea(
            child: Column(
              children: [
                // 顶部模式切换
                _buildModeSelector(),
                // 主功能区域
                Expanded(
                  child: _currentMode == 0
                      ? _buildTorchMode()
                      : _buildFloodLightMode(),
                ),
              ],
            ),
          ),
          // 全屏打光灯覆盖层
          if (_showFloodLightOverlay)
            _buildFloodLightOverlay(),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildModeButton(0, '🔦', '手电筒'),
          ),
          Expanded(
            child: _buildModeButton(1, '💡', '打光灯'),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(int mode, String emoji, String label) {
    final isSelected = _currentMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentMode = mode;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0A84FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF8E8E93),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTorchMode() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 手电筒图标/状态
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _isTorchOn ? _pulseAnimation.value : 1.0,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isTorchOn
                      ? const Color(0xFFFFD60A).withValues(alpha: 0.2)
                      : const Color(0xFF2C2C2E),
                  border: Border.all(
                    color: _isTorchOn
                        ? const Color(0xFFFFD60A)
                        : const Color(0xFF48484A),
                    width: 3,
                  ),
                  boxShadow: _isTorchOn
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFFD60A).withValues(alpha: 0.5),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  _isTorchOn ? Icons.flashlight_on : Icons.flashlight_off,
                  size: 80,
                  color: _isTorchOn
                      ? const Color(0xFFFFD60A)
                      : const Color(0xFF8E8E93),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 40),
        // 状态文字
        Text(
          _isTorchOn ? '手电筒已开启' : '点击开启手电筒',
          style: TextStyle(
            color: _isTorchOn ? const Color(0xFFFFD60A) : const Color(0xFF8E8E93),
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (!_torchAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '当前设备不支持闪光灯',
              style: TextStyle(
                color: Colors.red.withValues(alpha: 0.8),
                fontSize: 14,
              ),
            ),
          ),
        const SizedBox(height: 60),
        // 开关按钮
        _buildLargeButton(
          onTap: _torchAvailable ? _toggleTorch : _showPermissionDialog,
          icon: _isTorchOn ? Icons.power_settings_new : Icons.power,
          label: _isTorchOn ? '关闭' : '开启',
          color: _isTorchOn ? const Color(0xFFFF453A) : const Color(0xFF30D158),
          isEnabled: _torchAvailable,
        ),
      ],
    );
  }

  Widget _buildFloodLightMode() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 打光灯图标
        GestureDetector(
          onVerticalDragUpdate: (details) {
            // 上下滑动调整亮度
            setState(() {
              _floodLightBrightness = (_floodLightBrightness - details.delta.dy / 200)
                  .clamp(0.1, 1.0);
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isFloodLightOn
                  ? Color.lerp(
                      const Color(0xFFFF9F0A),
                      Colors.white,
                      1 - _floodLightBrightness,
                    )!.withValues(alpha: 0.3)
                  : const Color(0xFF2C2C2E),
              border: Border.all(
                color: _isFloodLightOn
                    ? Color.lerp(
                        const Color(0xFFFF9F0A),
                        Colors.white,
                        1 - _floodLightBrightness,
                      )!
                    : const Color(0xFF48484A),
                width: 3,
              ),
              boxShadow: _isFloodLightOn
                  ? [
                      BoxShadow(
                        color: Color.lerp(
                          const Color(0xFFFF9F0A),
                          Colors.white,
                          1 - _floodLightBrightness,
                        )!.withValues(alpha: 0.5),
                        blurRadius: 30 * _floodLightBrightness,
                        spreadRadius: 5 * _floodLightBrightness,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              _isFloodLightOn ? Icons.light_mode : Icons.lightbulb_outline,
              size: 70,
              color: _isFloodLightOn
                  ? Color.lerp(
                      const Color(0xFFFF9F0A),
                      Colors.white,
                      1 - _floodLightBrightness,
                    )
                  : const Color(0xFF8E8E93),
            ),
          ),
        ),
        const SizedBox(height: 40),
        Text(
          _isFloodLightOn ? '打光灯已开启' : '点击开启打光灯',
          style: TextStyle(
            color: _isFloodLightOn
                ? const Color(0xFFFF9F0A)
                : const Color(0xFF8E8E93),
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        // 上下滑动提示
        if (_isFloodLightOn)
          Text(
            '上下滑动图标调整亮度',
            style: TextStyle(
              color: const Color(0xFF8E8E93),
              fontSize: 13,
            ),
          ),
        const SizedBox(height: 8),
        // 亮度显示
        if (_isFloodLightOn)
          Text(
            '${(_floodLightBrightness * 100).toInt()}%',
            style: const TextStyle(
              color: Color(0xFFFF9F0A),
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
        const SizedBox(height: 40),
        // 全屏按钮
        _buildLargeButton(
          onTap: _toggleFloodLight,
          icon: _isFloodLightOn ? Icons.fullscreen_exit : Icons.fullscreen,
          label: _isFloodLightOn ? '全屏照亮' : '开启照亮',
          color: const Color(0xFFFF9F0A),
          isEnabled: true,
        ),
        if (_isFloodLightOn) ...[
          const SizedBox(height: 16),
          TextButton(
            onPressed: _closeFloodLight,
            child: const Text(
              '关闭',
              style: TextStyle(
                color: Color(0xFFFF453A),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLargeButton({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    required Color color,
    required bool isEnabled,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          color: isEnabled ? color.withValues(alpha: 0.15) : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isEnabled ? color : const Color(0xFF48484A),
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isEnabled ? color : const Color(0xFF8E8E93),
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isEnabled ? color : const Color(0xFF8E8E93),
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 全屏打光灯覆盖层 - 支持上下滑动调整亮度
  Widget _buildFloodLightOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          // 上下滑动调整亮度
          setState(() {
            _floodLightBrightness = (_floodLightBrightness - details.delta.dy / 200)
                .clamp(0.1, 1.0);
          });
        },
        onTap: _closeFloodLight,
        child: Container(
          color: Color.lerp(
            const Color(0xFFFF9F0A),
            Colors.white,
            1 - _floodLightBrightness,
          )!.withValues(alpha: 0.95),
          child: Stack(
            children: [
              // 顶部提示
              Positioned(
                top: MediaQuery.of(context).padding.top + 60,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '上下滑动调整亮度',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
              // 中间亮度显示
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.light_mode,
                      size: 80,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '${(_floodLightBrightness * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // 底部关闭按钮
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 40,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _closeFloodLight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close, color: Colors.white, size: 24),
                          SizedBox(width: 8),
                          Text(
                            '关闭',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void registerTorchDemo() {
  demoRegistry.register(TorchDemo());
}
