import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:torch_light/torch_light.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../lab_container.dart';

/// 手电筒 Demo
class TorchDemo extends DemoPage {
  @override
  String get title => '手电筒';

  @override
  String get description => '手电筒和屏幕亮度调节';

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

class _TorchPageState extends State<_TorchPage>
    with SingleTickerProviderStateMixin {
  // 手电筒状态
  bool _isTorchOn = false;
  bool _torchAvailable = false;

  // 屏幕光状态
  bool _isScreenLightOn = false;
  double _screenBrightness = 1.0;
  double _savedBrightness = 0.5;
  bool _keepScreenOn = false;

  // 模式
  int _currentMode = 0; // 0: 手电筒, 1: 屏幕光

  // 全屏屏幕光覆盖层
  bool _showScreenLightOverlay = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initScreenBrightness();
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
    _turnOffScreenLight();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initScreenBrightness() async {
    try {
      final brightness = await ScreenBrightness().current;
      setState(() {
        _screenBrightness = brightness ?? 0.5;
        _savedBrightness = _screenBrightness;
      });
    } catch (e) {
      debugPrint('Failed to get screen brightness: $e');
    }
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

  Future<void> _turnOnScreenLight() async {
    try {
      // 保存当前亮度
      _savedBrightness = await ScreenBrightness().current ?? 0.5;
      // 设置为最大亮度
      await ScreenBrightness().setScreenBrightness(1.0);
      if (_keepScreenOn) {
        await WakelockPlus.enable();
      }
      setState(() {
        _isScreenLightOn = true;
        _screenBrightness = 1.0;
        _showScreenLightOverlay = true;
      });
    } catch (e) {
      debugPrint('Screen light error: $e');
    }
  }

  Future<void> _turnOffScreenLight() async {
    if (_isScreenLightOn) {
      try {
        // 恢复之前亮度
        await ScreenBrightness().setScreenBrightness(_savedBrightness);
        await WakelockPlus.disable();
        setState(() {
          _isScreenLightOn = false;
          _showScreenLightOverlay = false;
          _screenBrightness = _savedBrightness;
        });
      } catch (e) {
        debugPrint('Turn off screen light error: $e');
      }
    }
  }

  Future<void> _setScreenBrightness(double value) async {
    setState(() {
      _screenBrightness = value;
    });
    if (_isScreenLightOn) {
      try {
        await ScreenBrightness().setScreenBrightness(value);
      } catch (e) {
        debugPrint('Set brightness error: $e');
      }
    }
  }

  Future<void> _toggleKeepScreenOn() async {
    setState(() {
      _keepScreenOn = !_keepScreenOn;
    });
    if (_keepScreenOn) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
    HapticFeedback.lightImpact();
  }

  void _closeScreenLight() {
    _turnOffScreenLight();
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
          SafeArea(
            child: Column(
              children: [
                _buildModeSelector(),
                Expanded(
                  child: _currentMode == 0
                      ? _buildTorchMode()
                      : _buildScreenLightMode(),
                ),
              ],
            ),
          ),
          if (_showScreenLightOverlay) _buildScreenLightOverlay(),
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
          Expanded(child: _buildModeButton(0, '🔦', '手电筒')),
          Expanded(child: _buildModeButton(1, '☀️', '屏幕光')),
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
        // 大图标可点击切换
        GestureDetector(
          onTap: _torchAvailable ? _toggleTorch : _showPermissionDialog,
          child: AnimatedBuilder(
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
                              color: const Color(
                                0xFFFFD60A,
                              ).withValues(alpha: 0.5),
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
        ),
        const SizedBox(height: 40),
        Text(
          _isTorchOn ? '点击关闭手电筒' : '点击开启手电筒',
          style: TextStyle(
            color: _isTorchOn
                ? const Color(0xFFFFD60A)
                : const Color(0xFF8E8E93),
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

  Widget _buildScreenLightMode() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 屏幕光图标
        GestureDetector(
          onVerticalDragUpdate: (details) {
            if (_isScreenLightOn) {
              _setScreenBrightness(
                (_screenBrightness - details.delta.dy / 200).clamp(0.1, 1.0),
              );
            }
          },
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isScreenLightOn
                  ? Color.lerp(
                      const Color(0xFF1C1C1E),
                      Colors.white,
                      _screenBrightness,
                    )
                  : const Color(0xFF2C2C2E),
              border: Border.all(
                color: _isScreenLightOn
                    ? Colors.white.withValues(alpha: 0.5)
                    : const Color(0xFF48484A),
                width: 3,
              ),
            ),
            child: Icon(
              _isScreenLightOn ? Icons.light_mode : Icons.lightbulb_outline,
              size: 70,
              color: _isScreenLightOn ? Colors.white : const Color(0xFF8E8E93),
            ),
          ),
        ),
        const SizedBox(height: 40),
        Text(
          _isScreenLightOn ? '屏幕光已开启' : '点击开启屏幕光',
          style: TextStyle(
            color: _isScreenLightOn ? Colors.white : const Color(0xFF8E8E93),
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (_isScreenLightOn) ...[
          const SizedBox(height: 16),
          Text(
            '上下滑动图标调整亮度',
            style: TextStyle(color: const Color(0xFF8E8E93), fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            '${(_screenBrightness * 100).toInt()}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 40),
        // 保持常亮开关
        if (_isScreenLightOn) ...[
          _buildKeepScreenOnSwitch(),
          const SizedBox(height: 20),
        ],
        _buildLargeButton(
          onTap: _isScreenLightOn ? _closeScreenLight : _turnOnScreenLight,
          icon: _isScreenLightOn ? Icons.fullscreen_exit : Icons.fullscreen,
          label: _isScreenLightOn ? '退出全屏' : '开启全屏',
          color: Colors.white,
          isEnabled: true,
        ),
      ],
    );
  }

  Widget _buildKeepScreenOnSwitch() {
    return GestureDetector(
      onTap: _toggleKeepScreenOn,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: _keepScreenOn
              ? const Color(0xFF30D158).withValues(alpha: 0.2)
              : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _keepScreenOn
                ? const Color(0xFF30D158)
                : const Color(0xFF48484A),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _keepScreenOn ? Icons.lock_outline : Icons.lock_open_outlined,
              size: 20,
              color: _keepScreenOn
                  ? const Color(0xFF30D158)
                  : const Color(0xFF8E8E93),
            ),
            const SizedBox(width: 8),
            Text(
              '保持常亮',
              style: TextStyle(
                color: _keepScreenOn
                    ? const Color(0xFF30D158)
                    : const Color(0xFF8E8E93),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 44,
              height: 26,
              decoration: BoxDecoration(
                color: _keepScreenOn
                    ? const Color(0xFF30D158)
                    : const Color(0xFF48484A),
                borderRadius: BorderRadius.circular(13),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: _keepScreenOn
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 全屏屏幕光覆盖层
  Widget _buildScreenLightOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          _setScreenBrightness(
            (_screenBrightness - details.delta.dy / 200).clamp(0.1, 1.0),
          );
        },
        child: Container(
          color: Color.lerp(
            const Color(0xFF1C1C1E),
            Colors.white,
            _screenBrightness,
          ),
          child: Stack(
            children: [
              // 顶部提示
              Positioned(
                top: MediaQuery.of(context).padding.top + 60,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '上下滑动调整亮度',
                      style: TextStyle(color: Colors.black87, fontSize: 14),
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
                      color: Colors.black.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '${(_screenBrightness * 100).toInt()}%',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.8),
                        fontSize: 48,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // 保持常亮开关
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 100,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _toggleKeepScreenOn,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _keepScreenOn
                                ? Icons.lock_outline
                                : Icons.lock_open_outlined,
                            size: 18,
                            color: _keepScreenOn
                                ? const Color(0xFF30D158)
                                : Colors.black54,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '常亮 ${_keepScreenOn ? "开" : "关"}',
                            style: TextStyle(
                              color: _keepScreenOn
                                  ? const Color(0xFF30D158)
                                  : Colors.black54,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // 底部关闭按钮
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 40,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _closeScreenLight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close, color: Colors.black87, size: 24),
                          SizedBox(width: 8),
                          Text(
                            '关闭',
                            style: TextStyle(
                              color: Colors.black87,
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
