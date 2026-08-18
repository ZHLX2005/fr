import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../domain/models.dart';
import '../../presentation/timetable_store.dart';
import 'timetable_import_dialog.dart';
import 'advanced/cycle_config_strategy.dart';
import 'advanced/shared/zen_controls.dart';
import '../../../../../widgets/theme/zen_theme.dart';

/// 课表高级设置页 —— 独立页面承载非常用数字配置。
///
/// 从主设置页拆出：周期配置 / 左侧指示显示控制 / DSL 导入导出 / 清空。
/// 起始日期属课表模式 UX 自动化，保留在主设置页第一层。
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

    // 周期配置策略决定实际生效的天数（课表固定 7 / 通用用用户值 / 番剧不落盘）
    final strategy = cycleStrategyFor(config);
    final daysToSave = strategy.resolveDaysPerCycle(_daysPerCycle);

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
    // 周期配置策略：课表/通用/番剧 三模式平级路由（fr 30），页面零模式分支
    final cycleStrategy = cycleStrategyFor(config);

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
          // ── 周期配置（3 模式策略驱动：课表固定7天/通用全可调/番剧自动派生）──
          ZenSection(
            title: '周期配置',
            child: cycleStrategy.buildCycleSection(
              cycleCount: _cycleCount,
              daysPerCycle: _daysPerCycle,
              slotsPerDay: _slotsPerDay,
              onCycleCountChanged: (v) => setState(() => _cycleCount = v),
              onDaysPerCycleChanged: (v) => setState(() => _daysPerCycle = v),
              onSlotsPerDayChanged: (v) {
                setState(() => _slotsPerDay = v);
                _ensureSlotLists();
              },
            ),
          ),
          const SizedBox(height: 12),
          // ── 每页显示行数（全模式通用：行数超出则纵向滚动）──
          ZenSection(
            title: '显示视口',
            child: ZenConfigSlider(
              label: '每页显示行数 '
                  '(${TimetableConfig.minSlotsPerPage}-${TimetableConfig.maxSlotsPerPage}，超出滚动)',
              value: _slotsPerPage.toDouble(),
              min: TimetableConfig.minSlotsPerPage.toDouble(),
              max: TimetableConfig.maxSlotsPerPage.toDouble(),
              divisions: TimetableConfig.maxSlotsPerPage -
                  TimetableConfig.minSlotsPerPage,
              onChanged: (v) {
                setState(() => _slotsPerPage = v.round());
              },
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
                      child: ZenSegmentButton(
                        label: '序号',
                        selected: _leftLabelMode == 0,
                        onTap: () => setState(() => _leftLabelMode = 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ZenSegmentButton(
                        label: '时间段',
                        selected: _leftLabelMode == 1,
                        onTap: () => setState(() => _leftLabelMode = 1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ZenSegmentButton(
                        label: '自定义',
                        selected: _leftLabelMode == 2,
                        onTap: () => setState(() => _leftLabelMode = 2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ZenConfigSlider(
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
                  ZenConfigSlider(
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
                ZenActionButton(
                  icon: Icons.upload_file,
                  label: '导入 DSL（含配置）',
                  onPressed: _openImport,
                ),
                const SizedBox(height: 8),
                ZenActionButton(
                  icon: Icons.download,
                  label: '导出 DSL（含配置）',
                  onPressed: _exportDsl,
                  secondary: true,
                ),
                const SizedBox(height: 8),
                ZenActionButton(
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
