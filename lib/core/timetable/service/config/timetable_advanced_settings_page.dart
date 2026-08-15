import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../domain/models.dart';
import '../../presentation/timetable_store.dart';
import 'timetable_import_dialog.dart';
import '../../../../../widgets/theme/zen_theme.dart';

/// 课表高级设置页 —— 独立页面承载非常用数字配置。
///
/// 从主设置页拆出：起始日期 / 周期配置 / 左侧指示显示控制 / DSL 导入导出 / 清空。
/// 主设置页只保留「模式选择 + 数据来源」第一层。
class TimetableAdvancedSettingsPage extends ConsumerStatefulWidget {
  const TimetableAdvancedSettingsPage({super.key});

  @override
  ConsumerState<TimetableAdvancedSettingsPage> createState() =>
      _TimetableAdvancedSettingsPageState();
}

class _TimetableAdvancedSettingsPageState
    extends ConsumerState<TimetableAdvancedSettingsPage> {
  late int _cycleCount;
  late int _daysPerCycle;
  late int _slotsPerDay;
  late int _slotsPerPage;
  late int _leftLabelMode;
  late double _leftWidth;
  late int _slotDurationMin;
  late List<String> _slotLabels;
  late List<String> _slotStartTimes;

  @override
  void initState() {
    super.initState();
    final config = ref.read(TimetableStore.provider).config;
    _cycleCount = config.cycleCount;
    _daysPerCycle = config.daysPerCycle;
    _slotsPerDay = config.slotsPerDay;
    _slotsPerPage = config.slotsPerPage;
    _leftLabelMode = config.leftLabelMode;
    _leftWidth = config.leftWidth;
    _slotDurationMin = config.slotDurationMin;
    _slotLabels = List<String>.from(config.slotLabels ?? const []);
    _slotStartTimes = List<String>.from(config.slotStartTimes ?? const []);
    _ensureSlotLists();
  }

  void _ensureSlotLists() {
    if (_slotLabels.length != _slotsPerDay) {
      _slotLabels = List.generate(
        _slotsPerDay,
        (i) => i < _slotLabels.length ? _slotLabels[i] : '',
      );
    }
    if (_slotStartTimes.length != _slotsPerDay) {
      _slotStartTimes = List.generate(
        _slotsPerDay,
        (i) => i < _slotStartTimes.length ? _slotStartTimes[i] : '',
      );
    }
  }

  List<String>? _trimmedOrNull(List<String> list) {
    final trimmed = List<String>.from(list);
    while (trimmed.isNotEmpty && trimmed.last.trim().isEmpty) {
      trimmed.removeLast();
    }
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _save() async {
    final store = ref.read(TimetableStore.provider.notifier);
    final config = ref.read(TimetableStore.provider).config;

    // 学校模式下强制 daysPerCycle = 7
    final daysToSave = config.isSchoolMode ? 7 : _daysPerCycle;

    _ensureSlotLists();
    final error = await store.updateConfig(
      cycleCount: _cycleCount,
      daysPerCycle: daysToSave,
      slotsPerDay: _slotsPerDay,
      slotsPerPage: _slotsPerPage,
      leftLabelMode: _leftLabelMode,
      leftWidth: _leftWidth,
      slotDurationMin: _slotDurationMin,
      slotLabels: _trimmedOrNull(_slotLabels),
      slotStartTimes: _trimmedOrNull(_slotStartTimes),
    );

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('高级设置已保存')));
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
            style: TextButton.styleFrom(foregroundColor: ZenColors.mutedRed),
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
    final config = ref.watch(TimetableStore.configProvider);
    final isSchoolMode = config.isSchoolMode;

    return zenPageScaffold(
      title: '高级设置',
      actions: [
        IconButton(
          icon: const Icon(Icons.save),
          tooltip: '保存',
          onPressed: _save,
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 周期配置（非常用数字配置）──
          ZenSection(
            title: '周期配置',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ZenConfigSlider(
                  label: '周期数',
                  value: _cycleCount.toDouble(),
                  min: TimetableConfig.minCycles.toDouble(),
                  max: TimetableConfig.maxCycles.toDouble(),
                  divisions:
                      TimetableConfig.maxCycles - TimetableConfig.minCycles,
                  onChanged: (v) => setState(() => _cycleCount = v.round()),
                ),
                if (isSchoolMode)
                  _ZenFixedLabel(label: '每周期天数', value: '7天（固定）')
                else
                  _ZenConfigSlider(
                    label: '每周期天数 (1-7)',
                    value: _daysPerCycle.toDouble(),
                    min: TimetableConfig.minDaysPerCycle.toDouble(),
                    max: TimetableConfig.maxDaysPerCycle.toDouble(),
                    divisions: TimetableConfig.maxDaysPerCycle -
                        TimetableConfig.minDaysPerCycle,
                    onChanged: (v) => setState(() => _daysPerCycle = v.round()),
                  ),
                // 学校/通用模式手动上限 6；追剧模式每剧独占 slot 允许到 64（fr 28）
                Builder(builder: (context) {
                  final isAnime = ref
                      .read(TimetableStore.provider)
                      .config
                      .isAnimeMode;
                  final slotMax = isAnime
                      ? TimetableConfig.maxSlotsPerDay
                      : TimetableConfig.maxManualSlotsPerDay;
                  return _ZenConfigSlider(
                    label: '每天节数 (1-$slotMax)',
                    value: _slotsPerDay.toDouble(),
                    min: TimetableConfig.minSlotsPerDay.toDouble(),
                    max: slotMax.toDouble(),
                    divisions: slotMax - TimetableConfig.minSlotsPerDay,
                    onChanged: (v) {
                      setState(() => _slotsPerDay = v.round());
                      _ensureSlotLists();
                    },
                  );
                }),
                _ZenConfigSlider(
                  label: '每页显示行数 '
                      '(${TimetableConfig.minSlotsPerPage}-${TimetableConfig.maxSlotsPerPage}，超出滚动)',
                  value: _slotsPerPage.toDouble(),
                  min: TimetableConfig.minSlotsPerPage.toDouble(),
                  max: TimetableConfig.maxSlotsPerPage.toDouble(),
                  divisions: TimetableConfig.maxSlotsPerPage -
                      TimetableConfig.minSlotsPerPage,
                  onChanged: (v) => setState(() => _slotsPerPage = v.round()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── 左侧指示显示控制 ──
          ZenSection(
            title: '左侧指示',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _ZenSegmentButton(
                        label: '序号',
                        selected: _leftLabelMode == 0,
                        onTap: () => setState(() => _leftLabelMode = 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ZenSegmentButton(
                        label: '时间段',
                        selected: _leftLabelMode == 1,
                        onTap: () => setState(() => _leftLabelMode = 1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ZenSegmentButton(
                        label: '自定义',
                        selected: _leftLabelMode == 2,
                        onTap: () => setState(() => _leftLabelMode = 2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _ZenConfigSlider(
                  label: '左侧宽度 (px)',
                  value: _leftWidth,
                  min: 44,
                  max: 110,
                  divisions: 33,
                  onChanged: (v) =>
                      setState(() => _leftWidth = v.roundToDouble()),
                ),
                if (_leftLabelMode == 1) ...[
                  const SizedBox(height: 4),
                  _ZenConfigSlider(
                    label: '每节时长 (分钟)',
                    value: _slotDurationMin.toDouble(),
                    min: 15,
                    max: 120,
                    divisions: 21,
                    onChanged: (v) =>
                        setState(() => _slotDurationMin = v.round()),
                  ),
                  const SizedBox(height: 8),
                  Text('每节开始时间（HH:mm，自动计算结束）', style: ZenText.label),
                  const SizedBox(height: 8),
                  _buildTimeFields(),
                ],
                if (_leftLabelMode == 2) ...[
                  const SizedBox(height: 8),
                  Text('每节自定义文字（留空回退序号）', style: ZenText.label),
                  const SizedBox(height: 8),
                  _buildLabelFields(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── DSL 管理 ──
          ZenSection(
            title: 'DSL 管理',
            child: Column(
              children: [
                _ZenActionButton(
                  icon: Icons.upload_file,
                  label: '导入 DSL（含配置）',
                  onPressed: _openImport,
                ),
                const SizedBox(height: 8),
                _ZenActionButton(
                  icon: Icons.download,
                  label: '导出 DSL（含配置）',
                  onPressed: _exportDsl,
                  secondary: true,
                ),
                const SizedBox(height: 8),
                _ZenActionButton(
                  icon: Icons.delete_outline,
                  label: '清空所有课程',
                  onPressed: _clearAll,
                  danger: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 时间段模式：每节开始时间输入（HH:mm）
  Widget _buildTimeFields() {
    _ensureSlotLists();
    return Column(
      children: [
        for (int i = 0; i < _slotsPerDay; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    '第${i + 1}节',
                    style: ZenText.body.copyWith(
                      color: ZenColors.secondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(text: _slotStartTimes[i]),
                    keyboardType: TextInputType.datetime,
                    onChanged: (v) => _slotStartTimes[i] = v.trim(),
                    decoration: InputDecoration(
                      hintText: '08:00',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: ZenColors.hair),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: ZenColors.hair),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildLabelFields() {
    _ensureSlotLists();
    return Column(
      children: [
        for (int i = 0; i < _slotsPerDay; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    '第${i + 1}节',
                    style: ZenText.body.copyWith(
                      color: ZenColors.secondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(text: _slotLabels[i]),
                    onChanged: (v) => _slotLabels[i] = v.trim(),
                    decoration: InputDecoration(
                      hintText: '如: 上午 / 09:00 更新',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: ZenColors.hair),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: ZenColors.hair),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ──────────────────── Zen 风格子组件 ────────────────────

class _ZenSegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ZenSegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? ZenColors.sage.withValues(alpha: 0.1) : Colors.transparent,
          border: Border.all(
            color: selected ? ZenColors.sage : ZenColors.hair,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? ZenColors.sage : ZenColors.secondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _ZenConfigSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _ZenConfigSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: ZenText.body.copyWith(fontWeight: FontWeight.w500)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: ZenColors.sage.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                value.round().toString(),
                style: ZenText.body.copyWith(
                  color: ZenColors.sage,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: ZenColors.sage,
            inactiveTrackColor: ZenColors.hair,
            thumbColor: ZenColors.sage,
            overlayColor: ZenColors.sage.withValues(alpha: 0.2),
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

class _ZenFixedLabel extends StatelessWidget {
  final String label;
  final String value;

  const _ZenFixedLabel({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: ZenText.body.copyWith(fontWeight: FontWeight.w500)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: ZenColors.sage.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              value,
              style: ZenText.body.copyWith(
                color: ZenColors.sage,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZenActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool danger;
  final bool secondary;

  const _ZenActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? ZenColors.mutedRed
        : (secondary ? ZenColors.secondary : ZenColors.sage);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: zenButton(
          foreground: color,
          border: color.withValues(alpha: 0.5),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label, style: ZenText.button.copyWith(color: color)),
      ),
    );
  }
}
