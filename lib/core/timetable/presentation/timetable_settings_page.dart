import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import 'timetable_store.dart';
import 'timetable_colors.dart';
import 'timetable_import_dialog.dart';
import 'timetable_week_calculator.dart';

/// 设置页面
class TimetableSettingsPage extends ConsumerStatefulWidget {
  const TimetableSettingsPage({super.key});

  @override
  ConsumerState<TimetableSettingsPage> createState() =>
      _TimetableSettingsPageState();
}

class _TimetableSettingsPageState extends ConsumerState<TimetableSettingsPage> {
  late final TextEditingController _startDateController;
  late int _cycleCount;
  late int _daysPerCycle;
  late int _slotsPerDay;
  late bool _isSchoolMode;

  @override
  void initState() {
    super.initState();
    final config = ref.read(TimetableStore.provider).config;
    _startDateController = TextEditingController(text: config.startDateIso);
    _cycleCount = config.cycleCount;
    _daysPerCycle = config.daysPerCycle;
    _slotsPerDay = config.slotsPerDay;
    _isSchoolMode = config.isSchoolMode;
  }

  @override
  void dispose() {
    _startDateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = ref.read(TimetableStore.provider.notifier);

    // 学校模式下强制 daysPerCycle = 7
    final daysToSave = _isSchoolMode ? 7 : _daysPerCycle;

    final error = await store.updateConfig(
      startDateIso: _startDateController.text.trim(),
      cycleCount: _cycleCount,
      daysPerCycle: daysToSave,
      slotsPerDay: _slotsPerDay,
      isSchoolMode: _isSchoolMode,
    );

    if (error != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('设置已保存')));
      Navigator.pop(context);
    }
  }

  Future<void> _openImport() async {
    final count = await showDialog<int>(
      context: context,
      builder: (_) => const TimetableImportDialog(),
    );
    if (count != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入 $count 门课程')));
    }
  }

  Future<void> _exportDsl() async {
    final dsl = ref.read(TimetableStore.provider.notifier).exportToDsl();
    if (dsl.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无课程可导出')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: dsl));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('DSL 已复制到剪贴板')));
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空确认'),
        content: const Text('确定要清空所有课程吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(TimetableStore.provider.notifier).clearAllItems();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已清空所有课程')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('时间配置'),
        backgroundColor: TimetableColors.surface,
        foregroundColor: TimetableColors.textPrimary,
      ),
      backgroundColor: TimetableColors.surfaceVariant,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 模式选择
          _buildModeSelector(theme),
          const SizedBox(height: 24),
          // 起始日期
          _buildDatePicker(theme),
          const SizedBox(height: 24),
          // 周期数
          _ConfigSlider(
            label: '周期数',
            value: _cycleCount.toDouble(),
            min: TimetableConfig.minCycles.toDouble(),
            max: TimetableConfig.maxCycles.toDouble(),
            divisions: TimetableConfig.maxCycles - TimetableConfig.minCycles,
            onChanged: (v) => setState(() => _cycleCount = v.round()),
          ),
          // 每周期天数（学校模式固定7天，隐藏 slider）
          if (_isSchoolMode)
            _FixedLabel(label: '每周期天数', value: '7天（固定）')
          else
            _ConfigSlider(
              label: '每周期天数 (1-7)',
              value: _daysPerCycle.toDouble(),
              min: TimetableConfig.minDaysPerCycle.toDouble(),
              max: TimetableConfig.maxDaysPerCycle.toDouble(),
              divisions:
                  TimetableConfig.maxDaysPerCycle -
                  TimetableConfig.minDaysPerCycle,
              onChanged: (v) => setState(() => _daysPerCycle = v.round()),
            ),
          // 每天节数
          _ConfigSlider(
            label: '每天节数 (1-6)',
            value: _slotsPerDay.toDouble(),
            min: TimetableConfig.minSlotsPerDay.toDouble(),
            max: TimetableConfig.maxSlotsPerDay.toDouble(),
            divisions:
                TimetableConfig.maxSlotsPerDay - TimetableConfig.minSlotsPerDay,
            onChanged: (v) => setState(() => _slotsPerDay = v.round()),
          ),
          // 学校模式：批量导入按钮
          if (_isSchoolMode) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _openImport,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: TimetableColors.accent, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.upload_file, color: TimetableColors.accent),
              label: const Text(
                '批量导入课程',
                style: TextStyle(
                  color: TimetableColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _exportDsl,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: TimetableColors.accent.withValues(alpha: 0.6), width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: Icon(Icons.download, color: TimetableColors.accent.withValues(alpha: 0.8)),
              label: Text(
                '导出 DSL',
                style: TextStyle(
                  color: TimetableColors.accent.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _clearAll,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Colors.red, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text(
                '清空所有课程',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _save,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: TimetableColors.accent, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.save, color: TimetableColors.accent),
            label: const Text(
              '保存设置',
              style: TextStyle(
                color: TimetableColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '课表模式',
          style: const TextStyle(
            color: TimetableColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: TimetableColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isSchoolMode = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _isSchoolMode
                          ? TimetableColors.accent.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(9),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '学校模式',
                        style: TextStyle(
                          color: _isSchoolMode
                              ? TimetableColors.accent
                              : TimetableColors.textSecondary,
                          fontWeight: _isSchoolMode
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isSchoolMode = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: !_isSchoolMode
                          ? TimetableColors.accent.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(9),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '通用模式',
                        style: TextStyle(
                          color: !_isSchoolMode
                              ? TimetableColors.accent
                              : TimetableColors.textSecondary,
                          fontWeight: !_isSchoolMode
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isSchoolMode)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '周一为起始日期，7天固定，支持批量导入',
              style: TextStyle(
                color: TimetableColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDatePicker(ThemeData theme) {
    if (_isSchoolMode) {
      return _WeekCalculatorField(
        controller: _startDateController,
        onDateApplied: (date) {
          setState(() {
            _startDateController.text = date;
          });
        },
      );
    }

    return TextField(
      controller: _startDateController,
      style: const TextStyle(color: TimetableColors.textPrimary),
      decoration: InputDecoration(
        labelText: _isSchoolMode ? '起始日期（周一）' : '起始日期',
        labelStyle: const TextStyle(color: TimetableColors.textSecondary),
        prefixIcon: const Icon(
          Icons.calendar_today,
          color: TimetableColors.accent,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest,
      ),
      readOnly: true,
      onTap: () async {
        final currentDate = DateTime.tryParse(_startDateController.text);
        final date = await showDatePicker(
          context: context,
          initialDate: currentDate ?? DateTime.now(),
          firstDate: DateTime(2024),
          lastDate: DateTime(2030),
          selectableDayPredicate: _isSchoolMode
              ? (d) => d.weekday == DateTime.monday
              : null,
        );
        if (date != null) {
          setState(() {
            _startDateController.text = date.toIso8601String().split('T')[0];
          });
        }
      },
    );
  }
}

class _ConfigSlider extends StatelessWidget {
  const _ConfigSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: TimetableColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: const Border(
                  left: BorderSide(
                    color: TimetableColors.textPrimary,
                    width: 3,
                  ),
                ),
                color: TimetableColors.selectedBg,
              ),
              child: Text(
                value.round().toString(),
                style: const TextStyle(
                  color: TimetableColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: TimetableColors.accent,
            inactiveTrackColor: TimetableColors.border,
            thumbColor: TimetableColors.accent,
            overlayColor: TimetableColors.accent.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// 固定值标签（学校模式 daysPerCycle 固定显示）
class _FixedLabel extends StatelessWidget {
  const _FixedLabel({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: TimetableColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: const Border(
                left: BorderSide(
                  color: TimetableColors.accent,
                  width: 3,
                ),
              ),
              color: TimetableColors.accent.withValues(alpha: 0.08),
            ),
            child: Text(
              value,
              style: const TextStyle(
                color: TimetableColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 学校模式：周数推算起始日期的入口字段
class _WeekCalculatorField extends StatelessWidget {
  const _WeekCalculatorField({
    required this.controller,
    required this.onDateApplied,
  });

  final TextEditingController controller;
  final ValueChanged<String> onDateApplied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () async {
        final date = await showDialog<String>(
          context: context,
          builder: (_) => const WeekCalculatorDialog(),
        );
        if (date != null) {
          onDateApplied(date);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TimetableColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month, color: TimetableColors.accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '起始日期（周一）',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: TimetableColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    controller.text,
                    style: const TextStyle(
                      color: TimetableColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: TimetableColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
