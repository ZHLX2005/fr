import 'package:flutter/material.dart';
import '../domain/models.dart';

/// 课表设置底部弹窗
class TimetableSettingsBottomSheet extends StatefulWidget {
  const TimetableSettingsBottomSheet({
    super.key,
    required this.currentConfig,
  });

  final TimetableConfig currentConfig;

  static Future<TimetableConfig?> show(
    BuildContext context, {
    required TimetableConfig currentConfig,
  }) {
    return showModalBottomSheet<TimetableConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => TimetableSettingsBottomSheet(
        currentConfig: currentConfig,
      ),
    );
  }

  @override
  State<TimetableSettingsBottomSheet> createState() => _TimetableSettingsBottomSheetState();
}

class _TimetableSettingsBottomSheetState extends State<TimetableSettingsBottomSheet> {
  late int _rows;
  late int _cols;

  @override
  void initState() {
    super.initState();
    _rows = widget.currentConfig.rows;
    _cols = widget.currentConfig.cols;
  }

  void _submit() {
    Navigator.pop(context, TimetableConfig(rows: _rows, cols: _cols));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题栏
              Row(
                children: [
                  Text('课表设置', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 行数配置（节次/纵向）
              _ConfigSlider(
                label: '节次数（行）',
                value: _rows,
                min: 4,
                max: 20,
                onChanged: (v) => setState(() => _rows = v.round()),
              ),
              const SizedBox(height: 16),

              // 列数配置（天数/横向）
              _ConfigSlider(
                label: '天数（列）',
                value: _cols,
                min: 3,
                max: 14,
                onChanged: (v) => setState(() => _cols = v.round()),
              ),
              const SizedBox(height: 8),

              // 预览信息
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '当前: ${_rows}节 × ${_cols}天 = ${_rows * _cols}个格子',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '注意: 缩小网格会删除越界课程',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // 保存按钮
              FilledButton(
                onPressed: _submit,
                child: const Text('保存设置'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigSlider extends StatelessWidget {
  const _ConfigSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.titleSmall),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '$value',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
