import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;

import '../lab_container.dart';

class RivePendulumDemo extends DemoPage {
  @override
  String get title => 'Rive 摆钟';

  @override
  String get description => 'Rive 摆钟动画展示';

  @override
  Widget buildPage(BuildContext context) {
    return const _RivePendulumPage();
  }
}

class _RivePendulumPage extends StatefulWidget {
  const _RivePendulumPage();

  @override
  State<_RivePendulumPage> createState() => _RivePendulumPageState();
}

class _RivePendulumPageState extends State<_RivePendulumPage> {
  late final rive.FileLoader _fileLoader = rive.FileLoader.fromAsset(
    'assets/rive/pendulum/pendulum.riv',
    riveFactory: rive.Factory.rive,
  );

  @override
  void dispose() {
    _fileLoader.dispose();
    super.dispose();
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
                  'Rive 摆钟',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pendulum 摆钟动画演示',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
                              return Container(
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
                                        'Pendulum Animation',
                                        style: theme.textTheme.labelLarge?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    Center(
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
                                                  error: state.error.toString(),
                                                ),
                                              rive.RiveLoaded() =>
                                                rive.RiveWidget(
                                                  controller: state.controller,
                                                  fit: rive.Fit.contain,
                                                ),
                                            },
                                      ),
                                    ),
                                  ],
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
                              Text('assets/rive/pendulum.riv'),
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

void registerRivePendulumDemo() {
  demoRegistry.register(RivePendulumDemo());
}
