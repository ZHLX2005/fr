import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;

import '../lab_container.dart';

class DemoLaboratoryDemo extends DemoPage {
  @override
  String get title => 'Demo 实验室';

  @override
  String get description => 'Rive 动画点击与拖拽实验页';

  @override
  Widget buildPage(BuildContext context) {
    return const _DemoLaboratoryPage();
  }
}

class _DemoLaboratoryPage extends StatefulWidget {
  const _DemoLaboratoryPage();

  @override
  State<_DemoLaboratoryPage> createState() => _DemoLaboratoryPageState();
}

class _DemoLaboratoryPageState extends State<_DemoLaboratoryPage> {
  late final rive.FileLoader _fileLoader = rive.FileLoader.fromAsset(
    'assets/rive/smiley_stress_reliever.riv',
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
        next.dx.clamp(-110.0, 110.0),
        next.dy.clamp(-150.0, 150.0),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.08),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Demo 实验室',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
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
                const SizedBox(height: 20),
                Expanded(
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    elevation: 0,
                    child: Column(
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final glow = 14 + math.min(_tapCount, 8) * 3;
                              return GestureDetector(
                                onTap: _handleTap,
                                onPanUpdate: _handlePanUpdate,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        theme.colorScheme.primary.withValues(
                                          alpha: 0.08,
                                        ),
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
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                      Center(
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          curve: Curves.easeOut,
                                          width: constraints.maxWidth * 0.7,
                                          height: constraints.maxHeight * 0.7,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              32,
                                            ),
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
                                              scale: _pressed ? 0.94 : 1.0,
                                              duration: const Duration(
                                                milliseconds: 180,
                                              ),
                                              curve: Curves.easeOutBack,
                                              child: rive.RiveWidgetBuilder(
                                                fileLoader: _fileLoader,
                                                builder: (context, state) =>
                                                    switch (state) {
                                                      rive.RiveLoading() =>
                                                        const Center(
                                                          child:
                                                              CircularProgressIndicator(),
                                                        ),
                                                      rive.RiveFailed() =>
                                                        _RiveErrorView(
                                                          error: state.error
                                                              .toString(),
                                                        ),
                                                      rive.RiveLoaded() =>
                                                        rive.RiveWidget(
                                                          controller:
                                                              state.controller,
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
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Rive Asset',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 6),
                              Text('assets/rive/smiley_stress_reliever.riv'),
                            ],
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

class _RiveErrorView extends StatelessWidget {
  final String error;

  const _RiveErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 42, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              'Rive 加载失败',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void registerDemoLaboratoryDemo() {
  demoRegistry.register(DemoLaboratoryDemo());
}
