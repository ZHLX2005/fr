import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;

import 'const_rive.dart';
import 'rive_error_view.dart';

/// Rive 实验室子页
///
/// 加载 smiley_stress_reliever.riv，支持点击舞台切换压力状态、拖拽移动位置。
/// 点击次数越多阴影 glow 越强，模拟"被戳笑脸"的累加反馈。
class RiveLabView extends StatefulWidget {
  const RiveLabView({super.key});

  @override
  State<RiveLabView> createState() => _RiveLabViewState();
}

class _RiveLabViewState extends State<RiveLabView> {
  late final rive.FileLoader _fileLoader = rive.FileLoader.fromAsset(
    RiveAssets.smiley,
    riveFactory: rive.Factory.rive,
  );

  Offset _offset = Offset.zero;
  bool _pressed = false;
  int _tapCount = 0;

  @override
  void dispose() {
    _fileLoader.dispose();
    super.dispose();
  }

  void _resetStage() {
    setState(() {
      _offset = Offset.zero;
      _pressed = false;
      _tapCount = 0;
    });
  }

  void _handleTap() {
    setState(() {
      _tapCount += 1;
      _pressed = !_pressed;
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    setState(() {
      final next = _offset + details.delta;
      _offset = Offset(
        next.dx.clamp(-RiveLabParams.maxOffsetX, RiveLabParams.maxOffsetX),
        next.dy.clamp(-RiveLabParams.maxOffsetY, RiveLabParams.maxOffsetY),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '点击舞台触发反馈，拖拽可移动动画位置。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _InfoChip(label: '点击次数', value: '$_tapCount'),
            _InfoChip(
              label: '偏移',
              value:
                  '${_offset.dx.round().toString().padLeft(3)} , ${_offset.dy.round().toString().padLeft(3)}',
            ),
            ActionChip(
              label: const Text('重置'),
              avatar: const Icon(Icons.refresh, size: 18),
              onPressed: _resetStage,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final glow = RiveLabParams.baseGlow +
                          math.min(_tapCount, 8) * RiveLabParams.glowPerTap;
                      return GestureDetector(
                        onTap: _handleTap,
                        onPanUpdate: _handlePanUpdate,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                theme.colorScheme.primary.withValues(alpha: 0.08),
                                theme.colorScheme.surfaceContainerLow,
                              ],
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                left: 16,
                                top: 16,
                                child: Text(
                                  'Tap or drag the stage',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Center(
                                child: AnimatedContainer(
                                  duration: RiveLabParams.animDuration,
                                  curve: Curves.easeOut,
                                  width: constraints.maxWidth * 0.7,
                                  height: constraints.maxHeight * 0.7,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(32),
                                    boxShadow: [
                                      BoxShadow(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.18),
                                        blurRadius: glow.toDouble(),
                                        spreadRadius: _pressed ? 6 : 0,
                                      ),
                                    ],
                                  ),
                                  child: Transform.translate(
                                    offset: _offset,
                                    child: AnimatedScale(
                                      scale:
                                          _pressed ? RiveLabParams.pressedScale : 1.0,
                                      duration: RiveLabParams.animDuration,
                                      curve: Curves.easeOutBack,
                                      child: rive.RiveWidgetBuilder(
                                        fileLoader: _fileLoader,
                                        builder: (context, state) =>
                                            switch (state) {
                                          rive.RiveLoading() => const Center(
                                              child: CircularProgressIndicator(),
                                            ),
                                          rive.RiveFailed() => RiveErrorView(
                                              error: state.error.toString(),
                                            ),
                                          rive.RiveLoaded() => rive.RiveWidget(
                                              controller: state.controller,
                                              fit: rive.Fit.contain,
                                            ),
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.55),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rive Asset',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        RiveAssets.smiley,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label: $value', style: theme.textTheme.labelLarge),
    );
  }
}