import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:torch_light/torch_light.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../lab_container.dart';
import 'torch/const_torch.dart';

/// 手电筒 Demo
class TorchDemo extends DemoPage {
  @override
  String get title => '手电筒';

  @override
  String get description => '手电筒和屏幕亮度调节，支持护眼颜色';

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

  // 颜色状态 - 默认护眼黄
  Color _selectedColor = EyeProtectionColors.warmYellow;

  // 模式: 0=手电筒, 1=屏幕光
  int _currentMode = 0;

  // 全屏覆盖层
  bool _showScreenLightOverlay = false;

  // 自动隐藏控制
  bool _showControls = true;
  Timer? _hideControlsTimer;

  // 颜色面板展开
  bool _showColorPanel = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initScreenBrightness();
    _checkTorchAvailability();

    _pulseController = AnimationController(
      vsync: this,
      duration: TorchConst.pulseDuration,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _cancelHideTimer();
    _turnOffTorch();
    _turnOffScreenLight();
    _pulseController.dispose();
    super.dispose();
  }

  // ===== 自动隐藏控制 =====
  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    if (_showScreenLightOverlay) {
      _hideControlsTimer = Timer(TorchConst.controlsHideDelay, () {
        if (mounted && _showScreenLightOverlay) {
          setState(() {
            _showControls = false;
            _showColorPanel = false;
          });
        }
      });
    }
  }

  void _cancelHideTimer() {
    _hideControlsTimer?.cancel();
  }

  void _resetHideTimer() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _startHideTimer();
  }

  // ===== 屏幕亮度 =====
  Future<void> _initScreenBrightness() async {
    try {
      final brightness = await ScreenBrightness().current;
      setState(() {
        _screenBrightness = brightness;
        _savedBrightness = _screenBrightness;
      });
    } catch (e) {
      debugPrint('Failed to get screen brightness: $e');
    }
  }

  Future<void> _setScreenBrightness(double value) async {
    final clamped = value.clamp(
      TorchConst.minBrightness,
      TorchConst.maxBrightness,
    );
    setState(() {
      _screenBrightness = clamped;
    });
    if (_isScreenLightOn) {
      try {
        await ScreenBrightness().setScreenBrightness(clamped);
      } catch (e) {
        debugPrint('Set brightness error: $e');
      }
    }
  }

  // ===== 手电筒 =====
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

  // ===== 屏幕光 =====
  Future<void> _turnOnScreenLight() async {
    try {
      _savedBrightness = await ScreenBrightness().current;
      await ScreenBrightness().setScreenBrightness(1.0);
      if (_keepScreenOn) {
        await WakelockPlus.enable();
      }
      setState(() {
        _isScreenLightOn = true;
        _screenBrightness = 1.0;
        _showScreenLightOverlay = true;
        _showControls = true;
      });
      _startHideTimer();
    } catch (e) {
      debugPrint('Screen light error: $e');
    }
  }

  Future<void> _turnOffScreenLight() async {
    if (_isScreenLightOn) {
      try {
        await ScreenBrightness().setScreenBrightness(_savedBrightness);
        await WakelockPlus.disable();
        setState(() {
          _isScreenLightOn = false;
          _showScreenLightOverlay = false;
          _showControls = true;
        });
        _cancelHideTimer();
      } catch (e) {
        debugPrint('Turn off screen light error: $e');
      }
    }
  }

  void _closeScreenLight() {
    _turnOffScreenLight();
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
    _resetHideTimer();
  }

  // ===== 颜色 =====
  Color _getDisplayColor() {
    final hsv = HSVColor.fromColor(_selectedColor);
    return HSVColor.fromAHSV(
      1.0,
      hsv.hue,
      hsv.saturation,
      hsv.value * _screenBrightness,
    ).toColor();
  }

  Color _getPureColor() {
    final hsv = HSVColor.fromColor(_selectedColor);
    return HSVColor.fromAHSV(1.0, hsv.hue, hsv.saturation, 1.0).toColor();
  }

  void _onHueChanged(double hue) {
    final hsv = HSVColor.fromColor(_selectedColor);
    setState(() {
      _selectedColor = HSVColor.fromAHSV(
        1.0,
        hue,
        hsv.saturation,
        hsv.value,
      ).toColor();
    });
    _resetHideTimer();
  }

  void _onSaturationChanged(double saturation) {
    final hsv = HSVColor.fromColor(_selectedColor);
    setState(() {
      _selectedColor = HSVColor.fromAHSV(
        1.0,
        hsv.hue,
        saturation.clamp(0.0, 1.0),
        hsv.value,
      ).toColor();
    });
    _resetHideTimer();
  }

  void _onPresetColorSelected(Color color) {
    setState(() {
      _selectedColor = color;
    });
    _resetHideTimer();
  }

  void _toggleColorPanel() {
    setState(() {
      _showColorPanel = !_showColorPanel;
    });
    _resetHideTimer();
  }

  // ===== 对话框 =====
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

  // ===== Build Methods =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TorchConst.backgroundDark,
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
        color: TorchConst.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: _buildModeButton(0, '手电筒', '手电筒')),
          Expanded(child: _buildModeButton(1, '屏幕光', '屏幕光')),
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
        duration: TorchConst.modeSwitchDuration,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? TorchConst.accentBlue : Colors.transparent,
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
                color: isSelected ? Colors.white : TorchConst.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 手电筒模式 ---
  Widget _buildTorchMode() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
                        ? TorchConst.accentYellow.withValues(alpha: 0.2)
                        : TorchConst.cardDark,
                    border: Border.all(
                      color: _isTorchOn
                          ? TorchConst.accentYellow
                          : TorchConst.borderDark,
                      width: 3,
                    ),
                    boxShadow: _isTorchOn
                        ? [
                            BoxShadow(
                              color: TorchConst.accentYellow.withValues(
                                alpha: 0.5,
                              ),
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
                        ? TorchConst.accentYellow
                        : TorchConst.textSecondary,
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
                ? TorchConst.accentYellow
                : TorchConst.textSecondary,
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
          color: _isTorchOn ? TorchConst.accentRed : TorchConst.accentGreen,
          isEnabled: _torchAvailable,
        ),
      ],
    );
  }

  // --- 屏幕光模式 ---
  Widget _buildScreenLightMode() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),
                  // 颜色预览圆
                  GestureDetector(
                    onVerticalDragUpdate: (details) {
                      _setScreenBrightness(
                        _screenBrightness -
                            details.delta.dy /
                                TorchConst.brightnessSwipeSensitivity,
                      );
                    },
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _getDisplayColor(),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _getPureColor().withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.light_mode,
                        size: 70,
                        color: _getDisplayColor().computeLuminance() > 0.5
                            ? Colors.black38
                            : Colors.white38,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '屏幕灯光',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '上下滑动预览亮度 · ${(_screenBrightness * 100).toInt()}%',
                    style: const TextStyle(
                      color: TorchConst.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 颜色控制区域 - 始终显示
                  _buildColorControlArea(),
                  const SizedBox(height: 16),
                  _buildKeepScreenOnSwitch(),
                  const SizedBox(height: 16),
                  _buildLargeButton(
                    onTap: _turnOnScreenLight,
                    icon: Icons.fullscreen,
                    label: '开启全屏',
                    color: Colors.white,
                    isEnabled: true,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 颜色控制区域（非全屏模式）
  Widget _buildColorControlArea() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TorchConst.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '灯光颜色',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _getPureColor(),
                  border: Border.all(color: Colors.white30),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 色相环
          _buildHueRing(size: 160),
          const SizedBox(height: 12),
          // 饱和度滑块
          _buildSaturationSlider(),
          const SizedBox(height: 12),
          // 预设颜色
          _buildPresetColors(),
        ],
      ),
    );
  }

  Widget _buildHueRing({double size = 160}) {
    final hsv = HSVColor.fromColor(_selectedColor);
    return GestureDetector(
      onPanDown: (details) => _handleHuePan(details.localPosition, size),
      onPanUpdate: (details) => _handleHuePan(details.localPosition, size),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _HueRingPainter(
            selectedHue: hsv.hue,
            saturation: hsv.saturation,
          ),
        ),
      ),
    );
  }

  void _handleHuePan(Offset localPosition, double size) {
    final center = Offset(size / 2, size / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final distance = sqrt(dx * dx + dy * dy);
    final outerRadius = size / 2;
    final innerRadius = outerRadius * 0.55;

    if (distance >= innerRadius - 15 && distance <= outerRadius + 15) {
      var angle = atan2(dy, dx);
      var hue = ((angle * 180 / pi) + 360) % 360;
      _onHueChanged(hue);
    }
  }

  Widget _buildSaturationSlider() {
    final saturation = HSVColor.fromColor(_selectedColor).saturation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '鲜艳度',
              style: TextStyle(
                color: TorchConst.textSecondary,
                fontSize: 13,
              ),
            ),
            Text(
              '${(saturation * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _getPureColor(),
            inactiveTrackColor: TorchConst.borderDark,
            thumbColor: Colors.white,
            overlayColor: Colors.white.withValues(alpha: 0.1),
            trackHeight: 4,
          ),
          child: Slider(
            value: saturation,
            min: 0.0,
            max: 1.0,
            onChanged: _onSaturationChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildPresetColors() {
    final presets = EyeProtectionColors.presets;
    final names = EyeProtectionColors.presetNames;

    // 分两行，平衡数量
    final half = (presets.length / 2).ceil();
    final firstRow = presets.sublist(0, half);
    final firstNames = names.sublist(0, half);
    final secondRow = presets.sublist(half);
    final secondNames = names.sublist(half);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildColorRow(firstRow, firstNames),
        if (secondRow.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildColorRow(secondRow, secondNames),
        ],
      ],
    );
  }

  Widget _buildColorRow(List<Color> colors, List<String> names) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(colors.length, (index) {
        final color = colors[index];
        final name = names[index];
        final isSelected = _selectedColor == color;
        return GestureDetector(
          onTap: () => _onPresetColorSelected(color),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                style: TextStyle(
                  color: isSelected ? Colors.white : TorchConst.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildKeepScreenOnSwitch() {
    return GestureDetector(
      onTap: _toggleKeepScreenOn,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: _keepScreenOn
              ? TorchConst.accentGreen.withValues(alpha: 0.2)
              : TorchConst.cardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _keepScreenOn
                ? TorchConst.accentGreen
                : TorchConst.borderDark,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _keepScreenOn ? Icons.lock_outline : Icons.lock_open_outlined,
              size: 20,
              color: _keepScreenOn
                  ? TorchConst.accentGreen
                  : TorchConst.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              '保持常亮',
              style: TextStyle(
                color: _keepScreenOn
                    ? TorchConst.accentGreen
                    : TorchConst.textSecondary,
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
                    ? TorchConst.accentGreen
                    : TorchConst.borderDark,
                borderRadius: BorderRadius.circular(13),
              ),
              child: AnimatedAlign(
                duration: TorchConst.modeSwitchDuration,
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

  // --- 全屏覆盖层 ---
  Widget _buildScreenLightOverlay() {
    final displayColor = _getDisplayColor();
    final isLight = displayColor.computeLuminance() > 0.5;

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _resetHideTimer,
        onVerticalDragUpdate: (details) {
          _resetHideTimer();
          _setScreenBrightness(
            _screenBrightness -
                details.delta.dy / TorchConst.brightnessSwipeSensitivity,
          );
        },
        child: Container(
          color: displayColor,
          child: AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: TorchConst.controlsFadeDuration,
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Stack(
                children: [
                  // 顶部亮度提示
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 40,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isLight
                              ? Colors.black.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '上下滑动调整亮度 · ${(_screenBrightness * 100).toInt()}%',
                          style: TextStyle(
                            color: isLight
                                ? Colors.black54
                                : Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 中间颜色控制
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 颜色调色按钮
                        GestureDetector(
                          onTap: _toggleColorPanel,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isLight
                                  ? Colors.black.withValues(alpha: 0.15)
                                  : Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _getPureColor(),
                                    border: Border.all(
                                      color: isLight
                                          ? Colors.black26
                                          : Colors.white30,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '调色',
                                  style: TextStyle(
                                    color: isLight
                                        ? Colors.black54
                                        : Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Icon(
                                  _showColorPanel
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  color: isLight
                                      ? Colors.black54
                                      : Colors.white70,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // 展开的颜色面板
                        AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          child: _showColorPanel
                              ? Container(
                                  margin: const EdgeInsets.only(top: 16),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: isLight
                                        ? Colors.black.withValues(
                                            alpha: 0.15,
                                          )
                                        : Colors.white.withValues(
                                            alpha: 0.15,
                                          ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildHueRing(size: 140),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: 240,
                                        child: _buildSaturationSlider(),
                                      ),
                                      const SizedBox(height: 8),
                                      _buildPresetColorsCompact(),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                  // 底部控制
                  Positioned(
                    bottom: MediaQuery.of(context).padding.bottom + 40,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 常亮开关
                          GestureDetector(
                            onTap: _toggleKeepScreenOn,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isLight
                                    ? Colors.black.withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.15),
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
                                        ? TorchConst.accentGreen
                                        : (isLight
                                            ? Colors.black54
                                            : Colors.white70),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '常亮',
                                    style: TextStyle(
                                      color: _keepScreenOn
                                          ? TorchConst.accentGreen
                                          : (isLight
                                              ? Colors.black54
                                              : Colors.white70),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // 关闭按钮
                          GestureDetector(
                            onTap: _closeScreenLight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isLight
                                    ? Colors.black.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.close,
                                    color: isLight
                                        ? Colors.black54
                                        : Colors.white70,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '关闭',
                                    style: TextStyle(
                                      color: isLight
                                          ? Colors.black54
                                          : Colors.white70,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresetColorsCompact() {
    final presets = EyeProtectionColors.presets;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: List.generate(presets.length, (index) {
        final color = presets[index];
        final isSelected = _selectedColor == color;
        return GestureDetector(
          onTap: () => _onPresetColorSelected(color),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 2,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ===== 环形色相选择器绘制器 =====
class _HueRingPainter extends CustomPainter {
  final double selectedHue;
  final double saturation;

  _HueRingPainter({
    required this.selectedHue,
    required this.saturation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final innerRadius = outerRadius * 0.55;

    const segments = 120;
    for (int i = 0; i < segments; i++) {
      final startAngle = (i / segments) * 2 * pi - pi / 2;
      final endAngle = ((i + 1) / segments) * 2 * pi - pi / 2;
      final hue = (i / segments) * 360;
      final color = HSVColor.fromAHSV(1.0, hue, saturation, 1.0).toColor();

      final paint = Paint()..color = color;
      final path = Path();

      path.moveTo(
        center.dx + innerRadius * cos(startAngle),
        center.dy + innerRadius * sin(startAngle),
      );
      path.lineTo(
        center.dx + outerRadius * cos(startAngle),
        center.dy + outerRadius * sin(startAngle),
      );
      path.arcToPoint(
        Offset(
          center.dx + outerRadius * cos(endAngle),
          center.dy + outerRadius * sin(endAngle),
        ),
        radius: Radius.circular(outerRadius),
        clockwise: true,
      );
      path.lineTo(
        center.dx + innerRadius * cos(endAngle),
        center.dy + innerRadius * sin(endAngle),
      );
      path.arcToPoint(
        Offset(
          center.dx + innerRadius * cos(startAngle),
          center.dy + innerRadius * sin(startAngle),
        ),
        radius: Radius.circular(innerRadius),
        clockwise: false,
      );
      path.close();

      canvas.drawPath(path, paint);
    }

    // 选中指示器
    final indicatorAngle = (selectedHue / 360) * 2 * pi - pi / 2;
    final indicatorRadius = (outerRadius + innerRadius) / 2;
    final indicatorPos = Offset(
      center.dx + indicatorRadius * cos(indicatorAngle),
      center.dy + indicatorRadius * sin(indicatorAngle),
    );

    canvas.drawCircle(
      indicatorPos,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      indicatorPos,
      8,
      Paint()
        ..color = Colors.black38
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 中心圆显示当前颜色
    final centerColor = HSVColor.fromAHSV(
      1.0,
      selectedHue,
      saturation,
      1.0,
    ).toColor();
    canvas.drawCircle(
      center,
      innerRadius * 0.9,
      Paint()
        ..color = centerColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      innerRadius * 0.9,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _HueRingPainter oldDelegate) {
    return oldDelegate.selectedHue != selectedHue ||
        oldDelegate.saturation != saturation;
  }
}

void registerTorchDemo() {
  demoRegistry.register(TorchDemo());
}
