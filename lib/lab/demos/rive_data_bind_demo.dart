import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;

import '../lab_container.dart';

/// Rive 数据绑定 Demo
/// 展示 Flutter 与 Rive 状态机布尔输入的实时映射交互
class RiveDataBindDemo extends DemoPage {
  @override
  String get title => 'Rive 数据绑定';

  @override
  String get description => 'Rive 状态机布尔输入与 Flutter 双向数据映射';

  @override
  Widget buildPage(BuildContext context) => const _RiveDataBindPage();
}

class _RiveDataBindPage extends StatefulWidget {
  const _RiveDataBindPage();

  @override
  State<_RiveDataBindPage> createState() => _RiveDataBindPageState();
}

class _RiveDataBindPageState extends State<_RiveDataBindPage> {
  late final rive.FileLoader _fileLoader = rive.FileLoader.fromAsset(
    'assets/rive/input_machine/input_machine.riv',
    riveFactory: rive.Factory.rive,
  );

  rive.ViewModelInstanceBoolean? _inInput;
  bool _inputValue = false;
  bool _inputFound = false;

  @override
  void dispose() {
    _inInput?.dispose();
    _fileLoader.dispose();
    super.dispose();
  }

  void _extractInput(rive.RiveLoaded state) {
    if (_inInput != null) return;
    try {
      final vmi = state.controller.dataBind(rive.DataBind.auto());
      final input = vmi.boolean('in_input');
      if (input != null && mounted) {
        setState(() {
          _inInput = input;
          _inputFound = true;
          _inputValue = input.value;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _inputFound = false);
    }
  }

  void _setInput(bool value) {
    setState(() {
      _inputValue = value;
      _inInput?.value = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primary.withValues(alpha: 0.08),
              colorScheme.surface,
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
                  'Rive 数据绑定',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Flutter 状态与 Rive 状态机布尔输入 in_input 实时同步',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _buildStatusChips(theme, colorScheme),
                const SizedBox(height: 20),
                Expanded(
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    elevation: 0,
                    child: Column(
                      children: [
                        Expanded(
                          child: _buildRiveView(theme, colorScheme),
                        ),
                        _buildControlPanel(theme, colorScheme),
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

  Widget _buildStatusChips(ThemeData theme, ColorScheme colorScheme) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _InfoChip(
          label: '输入状态',
          value: _inputValue ? 'true' : 'false',
          color: _inputValue
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        ),
        _InfoChip(
          label: '绑定状态',
          value: _inputFound ? '已连接' : '未连接',
          color: _inputFound ? Colors.green : colorScheme.error,
        ),
      ],
    );
  }

  Widget _buildRiveView(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: 0.08),
            colorScheme.surfaceContainerLow,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 16,
            top: 16,
            child: Text(
              'Rive Animation',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Center(
            child: rive.RiveWidgetBuilder(
              fileLoader: _fileLoader,
              builder: (context, state) {
                if (state is rive.RiveLoaded && _inInput == null) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _extractInput(state),
                  );
                }
                return switch (state) {
                  rive.RiveLoading() => const Center(
                      child: CircularProgressIndicator(),
                    ),
                  rive.RiveFailed() => _RiveErrorView(
                      error: state.error.toString(),
                    ),
                  rive.RiveLoaded() => rive.RiveWidget(
                      controller: state.controller,
                      fit: rive.Fit.contain,
                    ),
                };
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Flutter 控制面板',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ToggleCard(
                  label: 'in_input',
                  value: _inputValue,
                  enabled: _inputFound,
                  onChanged: _inputFound ? _setInput : null,
                  activeColor: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionCard(
                  label: '脉冲触发',
                  icon: Icons.bolt,
                  enabled: _inputFound,
                  onTap: _inputFound
                      ? () async {
                          _setInput(true);
                          await Future.delayed(const Duration(milliseconds: 300));
                          if (mounted) _setInput(false);
                        }
                      : null,
                  color: colorScheme.tertiary,
                ),
              ),
            ],
          ),
          if (!_inputFound) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '未找到 in_input 布尔属性。请确保 Rive 文件通过 ViewModel 绑定了名为 in_input 的布尔属性。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _InfoChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text('$label: ', style: theme.textTheme.labelLarge),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleCard extends StatelessWidget {
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChanged;
  final Color activeColor;

  const _ToggleCard({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: enabled
          ? (value
              ? activeColor.withValues(alpha: 0.12)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.7))
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? () => onChanged?.call(!value) : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: value ? activeColor : Colors.transparent,
                  border: Border.all(
                    color: enabled
                        ? (value ? activeColor : colorScheme.outline)
                        : colorScheme.outline.withValues(alpha: 0.3),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: value
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? colorScheme.onSurface
                            : colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value ? '开启' : '关闭',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: enabled
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
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

class _ActionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;
  final Color color;

  const _ActionCard({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: enabled
          ? color.withValues(alpha: 0.12)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: enabled
                    ? color
                    : colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: enabled
                        ? colorScheme.onSurface
                        : colorScheme.onSurface.withValues(alpha: 0.4),
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

void registerRiveDataBindDemo() {
  demoRegistry.register(RiveDataBindDemo());
}
