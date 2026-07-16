import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;

import 'const_rive.dart';
import 'rive_error_view.dart';

/// Rive 摆钟子页
///
/// 加载 pendulum.riv 并居中播放。提供加载/失败/成功三态分支。
class RivePendulumView extends StatefulWidget {
  const RivePendulumView({super.key});

  @override
  State<RivePendulumView> createState() => _RivePendulumViewState();
}

class _RivePendulumViewState extends State<RivePendulumView> {
  late final rive.FileLoader _fileLoader = rive.FileLoader.fromAsset(
    RiveAssets.pendulum,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                                'Pendulum Animation',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Center(
                              child: rive.RiveWidgetBuilder(
                                fileLoader: _fileLoader,
                                builder: (context, state) => switch (state) {
                                  rive.RiveLoading() => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  rive.RiveFailed() =>
                                    RiveErrorView(error: state.error.toString()),
                                  rive.RiveLoaded() => rive.RiveWidget(
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
                        RiveAssets.pendulum,
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