import 'package:flutter/material.dart';
import 'dart:ui';
import '../lab_container.dart';

/// 液态玻璃Demo
class LiquidGlassDemo extends DemoPage {
  @override
  String get title => '液态玻璃';

  @override
  String get description => 'iOS 26 Liquid Glass 效果演示';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const LiquidGlassDemoPage();
  }
}

void registerLiquidGlassDemo() {
  demoRegistry.register(LiquidGlassDemo());
}

class LiquidGlassDemoPage extends StatelessWidget {
  const LiquidGlassDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 渐变背景
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF667eea),
                  Color(0xFF764ba2),
                  Color(0xFFf093fb),
                ],
              ),
            ),
          ),
          // 背景装饰圆
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.pink.withOpacity(0.6),
                    Colors.pink.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.blue.withOpacity(0.5),
                    Colors.blue.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          // 内容
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    'Liquid Glass',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'iOS 26 液态玻璃效果',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  // 基础卡片
                  _LiquidGlassCard(
                    child: const Text(
                      '基础液态玻璃卡片',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 按钮
                  _LiquidGlassButton(
                    onPressed: () {},
                    child: const Text(
                      '液态玻璃按钮',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 输入框
                  _LiquidGlassTextField(
                    hintText: '输入文字...',
                    onChanged: (v) {},
                  ),
                  const SizedBox(height: 20),
                  // 滑块
                  _LiquidGlassSlider(
                    value: 0.5,
                    onChanged: (v) {},
                  ),
                  const SizedBox(height: 20),
                  // 开关
                  _LiquidGlassSwitch(
                    value: true,
                    onChanged: (v) {},
                  ),
                  const SizedBox(height: 20),
                  // 信用卡卡片
                  const _LiquidGlassCreditCard(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 液态玻璃卡片组件
class _LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsets padding;

  const _LiquidGlassCard({
    required this.child,
    this.borderRadius = 20,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.25),
                Colors.white.withOpacity(0.1),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 液态玻璃按钮
class _LiquidGlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final double borderRadius;

  const _LiquidGlassButton({
    required this.child,
    this.onPressed,
    this.borderRadius = 30,
  });

  @override
  State<_LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<_LiquidGlassButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed?.call();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _isPressed
                      ? [
                          Colors.white.withOpacity(0.35),
                          Colors.white.withOpacity(0.2),
                        ]
                      : [
                          Colors.white.withOpacity(0.25),
                          Colors.white.withOpacity(0.15),
                        ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(widget.borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(_isPressed ? 0.05 : 0.1),
                    blurRadius: _isPressed ? 10 : 20,
                    offset: Offset(0, _isPressed ? 5 : 10),
                  ),
                ],
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 液态玻璃输入框
class _LiquidGlassTextField extends StatelessWidget {
  final String hintText;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;

  const _LiquidGlassTextField({
    required this.hintText,
    this.onChanged,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ),
    );
  }
}

/// 液态玻璃滑块
class _LiquidGlassSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;

  const _LiquidGlassSlider({
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _LiquidGlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '透明度',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withOpacity(0.2),
              thumbColor: Colors.white,
              overlayColor: Colors.white.withOpacity(0.1),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: value,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// 液态玻璃开关
class _LiquidGlassSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _LiquidGlassSwitch({
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _LiquidGlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '深色模式',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: Colors.white.withOpacity(0.3),
            inactiveThumbColor: Colors.white70,
            inactiveTrackColor: Colors.white.withOpacity(0.1),
          ),
        ],
      ),
    );
  }
}

/// 液态玻璃信用卡
class _LiquidGlassCreditCard extends StatelessWidget {
  const _LiquidGlassCreditCard();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1a1a2e),
                Color(0xFF16213e),
                Color(0xFF0f3460),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              // 光效
              Positioned(
                top: -30,
                right: -30,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.purple.withOpacity(0.6),
                        Colors.purple.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -20,
                left: -20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.blue.withOpacity(0.5),
                        Colors.blue.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // 内容
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'LIQUID',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        Container(
                          width: 40,
                          height: 30,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.credit_card,
                            color: Colors.white54,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      '••••  ••••  ••••  1234',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        letterSpacing: 3,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '持卡人',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 10,
                              ),
                            ),
                            const Text(
                              'LIQUID GLASS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '有效期',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 10,
                              ),
                            ),
                            const Text(
                              '12/28',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
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
}
