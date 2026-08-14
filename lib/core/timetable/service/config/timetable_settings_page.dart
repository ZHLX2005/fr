import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../domain/models.dart';
import '../../presentation/timetable_store.dart';
import 'anime_dsl_generator.dart';
import 'sicau_import_dialog.dart';
import 'timetable_anime_import_dialog.dart';
import 'timetable_import_dialog.dart';
import 'timetable_week_calculator.dart';
import '../../../../widgets/theme/zen_theme.dart';

/// 课表设置页 —— 沿用 Zen 设计系统组件（zenCard/ZenSection/zenButton）。
/// 课表主页面（timetable_page）使用 TimetableColors 自己的配色保持稳定，不动。
class TimetableSettingsPage extends ConsumerStatefulWidget {
  const TimetableSettingsPage({super.key});

  @override
  ConsumerState<TimetableSettingsPage> createState() =>
      _TimetableSettingsPageState();
}

class _TimetableSettingsPageState
    extends ConsumerState<TimetableSettingsPage> {
  late final TextEditingController _startDateController;
  late int _cycleCount;
  late int _daysPerCycle;
  late int _slotsPerDay;
  late bool _isSchoolMode;
  late bool _isAnimeMode;
  late int _leftLabelMode;
  late double _leftWidth;
  late int _slotDurationMin;
  late List<String> _slotLabels;
  late List<String> _slotStartTimes;
  final List<_AnimeInputRow> _animeRows = [];

  @override
  void initState() {
    super.initState();
    final config = ref.read(TimetableStore.provider).config;
    _startDateController = TextEditingController(text: config.startDateIso);
    _cycleCount = config.cycleCount;
    _daysPerCycle = config.daysPerCycle;
    _slotsPerDay = config.slotsPerDay;
    _isSchoolMode = config.isSchoolMode;
    _isAnimeMode = config.isAnimeMode;
    _leftLabelMode = config.leftLabelMode;
    _leftWidth = config.leftWidth;
    _slotDurationMin = config.slotDurationMin;
    _slotLabels = List<String>.from(config.slotLabels ?? const []);
    _slotStartTimes = List<String>.from(config.slotStartTimes ?? const []);
    _ensureSlotLists();
    _animeRows.add(_AnimeInputRow());
  }

  /// 保持标签/时间列表长度与 slotsPerDay 对齐（缺位补空串）
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

  /// 去掉列表尾部的空串（保存时 null 语义：无数据）
  List<String>? _trimmedOrNull(List<String> list) {
    final trimmed = List<String>.from(list);
    while (trimmed.isNotEmpty && trimmed.last.trim().isEmpty) {
      trimmed.removeLast();
    }
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  void dispose() {
    _startDateController.dispose();
    for (final row in _animeRows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final store = ref.read(TimetableStore.provider.notifier);

    // 通用模式原样保存；学校模式回退到最近周一（fr #2）
    final rawStart = _startDateController.text.trim();
    final startDateIso = resolveStartDateIso(
      rawStart,
      isSchoolMode: _isSchoolMode,
    );
    if (startDateIso != rawStart) {
      _startDateController.text = startDateIso;
    }

    // 学校模式下强制 daysPerCycle = 7
    final daysToSave = _isSchoolMode ? 7 : _daysPerCycle;

    _ensureSlotLists();
    final error = await store.updateConfig(
      startDateIso: startDateIso,
      cycleCount: _cycleCount,
      daysPerCycle: daysToSave,
      slotsPerDay: _slotsPerDay,
      isSchoolMode: _isSchoolMode,
      isAnimeMode: _isAnimeMode,
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
      ).showSnackBar(SnackBar(content: Text('设置已保存（起始日期 $startDateIso）')));
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

  Future<void> _openSicauImport() async {
    final count = await showDialog<int>(
      context: context,
      builder: (_) => const SicauImportDialog(),
    );
    if (count != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已从教务系统导入 $count 门课程')));
    }
  }

  Future<void> _openAnimeImport() async {
    final count = await showDialog<int>(
      context: context,
      builder: (_) => const TimetableAnimeImportDialog(),
    );
    if (count != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入 $count 部新番更新时间')));
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
    return zenPageScaffold(
      title: '时间配置',
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
          // ── 模式选择 ──
          ZenSection(
            title: '课表模式',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildModeSelector(),
                if (_isSchoolMode) ...[
                  const SizedBox(height: 8),
                  Text(
                    '学校模式：周一为起始日期，7天固定，支持批量导入',
                    style: ZenText.label.copyWith(fontSize: 12),
                  ),
                ],
                if (_isAnimeMode) ...[
                  const SizedBox(height: 8),
                  Text(
                    '追剧模式：输入剧的开始日期/星期/播出时间/期数，自动计算行列与周期',
                    style: ZenText.label.copyWith(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_isAnimeMode) ...[
            // ── 追剧/番模式：剧输入 → 自动生成 DSL ──
            ZenSection(
              title: '追剧 / 番模式',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._animeRows.asMap().entries.map(
                    (e) => _buildAnimeRow(e.key, e.value),
                  ),
                  const SizedBox(height: 8),
                  _ZenActionButton(
                    icon: Icons.add,
                    label: '添加一部剧',
                    onPressed: () => setState(() => _animeRows.add(_AnimeInputRow())),
                    secondary: true,
                  ),
                  const SizedBox(height: 12),
                  _ZenActionButton(
                    icon: Icons.auto_awesome,
                    label: '生成追剧 DSL',
                    onPressed: _generateAnimeDsl,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '自动对齐周一，按播出时间分组为竖直 cell，周期数由最长覆盖自动膨胀/收缩',
                    style: ZenText.label.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            // ── 起始日期 ──
            ZenSection(
              title: '起始日期',
              child: _buildDateField(),
            ),
            const SizedBox(height: 12),
            // ── 周期配置 ──
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
                  if (_isSchoolMode)
                    _ZenFixedLabel(
                      label: '每周期天数',
                      value: '7天（固定）',
                    )
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
                  _ZenConfigSlider(
                    label: '每天节数 (1-6)',
                    value: _slotsPerDay.toDouble(),
                    min: TimetableConfig.minSlotsPerDay.toDouble(),
                    max: TimetableConfig.maxSlotsPerDay.toDouble(),
                    divisions: TimetableConfig.maxSlotsPerDay -
                        TimetableConfig.minSlotsPerDay,
                    onChanged: (v) => setState(() => _slotsPerDay = v.round()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // ── 高级功能：左侧指示 / DSL 导入导出 / 清空 ──
          ZenSection(
            title: '高级功能',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    '左侧指示显示控制',
                    style: ZenText.body.copyWith(fontWeight: FontWeight.w500),
                  ),
                  childrenPadding: const EdgeInsets.only(top: 8),
                  children: [
                    _buildAdvancedControls(),
                  ],
                ),
                const SizedBox(height: 4),
                _ZenActionButton(
                  icon: Icons.upload_file,
                  label: '导入 DSL（含配置）',
                  onPressed: _openImport,
                  secondary: true,
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
          const SizedBox(height: 12),
          // ── 第一层数据来源（模式预设）：学校模式保留 SICAU 导入 ──
          if (_isSchoolMode) ...[
            ZenSection(
              title: '数据来源',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ZenActionButton(
                    icon: Icons.school,
                    label: 'SICAU 课表导入',
                    onPressed: _openSicauImport,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '更多导入 / 导出入口在下方「高级功能」',
                    style: ZenText.label.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_isAnimeMode) ...[
            // 追剧模式：Bangumi 新番作为另一个数据源预设
            ZenSection(
              title: '数据来源',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ZenActionButton(
                    icon: Icons.movie_outlined,
                    label: '从 Bangumi 拉取新番列表',
                    onPressed: _openAnimeImport,
                    secondary: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  // ──── 子组件：模式选择 ────
  Widget _buildModeSelector() {
    return Row(
      children: [
        Expanded(
          child: _ZenSegmentButton(
            label: '学校模式',
            selected: _isSchoolMode && !_isAnimeMode,
            onTap: () => setState(() {
              _isSchoolMode = true;
              _isAnimeMode = false;
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ZenSegmentButton(
            label: '通用模式',
            selected: !_isSchoolMode && !_isAnimeMode,
            onTap: () => setState(() {
              _isSchoolMode = false;
              _isAnimeMode = false;
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ZenSegmentButton(
            label: '追剧模式',
            selected: _isAnimeMode,
            onTap: () => setState(() {
              _isAnimeMode = true;
              _isSchoolMode = false;
            }),
          ),
        ),
      ],
    );
  }

  /// 高级功能：左侧指示显示控制（模式/宽度/时长/时间/自定义文字）
  Widget _buildAdvancedControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('左侧指示', style: ZenText.label),
        const SizedBox(height: 8),
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
          onChanged: (v) => setState(() => _leftWidth = v.roundToDouble()),
        ),
        if (_leftLabelMode == 1) ...[
          const SizedBox(height: 4),
          _ZenConfigSlider(
            label: '每节时长 (分钟)',
            value: _slotDurationMin.toDouble(),
            min: 15,
            max: 120,
            divisions: 21,
            onChanged: (v) => setState(() => _slotDurationMin = v.round()),
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
    );
  }

  // ──── 追剧模式：剧输入行 ────
  Widget _buildAnimeRow(int index, _AnimeInputRow row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: zenCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.titleCtrl,
                  decoration: const InputDecoration(
                    hintText: '剧名',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _animeRows.removeAt(index)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: InkWell(
                  onTap: () async {
                    final current = DateTime.tryParse(row.startDateCtrl.text);
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: current ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      helpText: '开始日期',
                    );
                    if (picked == null) return;
                    setState(() {
                      row.startDateCtrl.text =
                          picked.toIso8601String().split('T')[0];
                    });
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '开始日期',
                      isDense: true,
                    ),
                    child: Text(
                      row.startDateCtrl.text.isEmpty
                          ? '选择日期'
                          : row.startDateCtrl.text,
                      style: ZenText.body,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  initialValue: row.weekday,
                  isDense: true,
                  decoration: const InputDecoration(labelText: '星期'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('周一')),
                    DropdownMenuItem(value: 2, child: Text('周二')),
                    DropdownMenuItem(value: 3, child: Text('周三')),
                    DropdownMenuItem(value: 4, child: Text('周四')),
                    DropdownMenuItem(value: 5, child: Text('周五')),
                    DropdownMenuItem(value: 6, child: Text('周六')),
                    DropdownMenuItem(value: 7, child: Text('周日')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => row.weekday = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.timeCtrl,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(
                    labelText: '播出时间 HH:mm',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.episodesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '总期数',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '每期分钟',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 追剧模式：收集输入 → 生成 DSL → 预览 → 应用
  Future<void> _generateAnimeDsl() async {
    final inputs = <AnimeSeriesInput>[];
    final errors = <String>[];
    for (var i = 0; i < _animeRows.length; i++) {
      final row = _animeRows[i];
      final title = row.titleCtrl.text.trim();
      final start = row.startDateCtrl.text.trim();
      final time = row.timeCtrl.text.trim();
      final episodes = int.tryParse(row.episodesCtrl.text.trim());
      final duration = int.tryParse(row.durationCtrl.text.trim());
      if (title.isEmpty || start.isEmpty || time.isEmpty) {
        errors.add('第 ${i + 1} 部：剧名/开始日期/播出时间 必填');
        continue;
      }
      if (DateTime.tryParse(start) == null) {
        errors.add('第 ${i + 1} 部：开始日期无效 $start');
        continue;
      }
      if (!RegExp(r'^\d{1,2}:\d{2}$').hasMatch(time)) {
        errors.add('第 ${i + 1} 部：播出时间应为 HH:mm');
        continue;
      }
      if (episodes == null || episodes < 1) {
        errors.add('第 ${i + 1} 部：期数应为正整数');
        continue;
      }
      inputs.add(
        AnimeSeriesInput(
          title: title,
          startDateIso: start,
          weekday: row.weekday,
          time: time,
          episodes: episodes,
          durationMin: duration ?? 45,
        ),
      );
    }
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errors.join('\n'))));
      return;
    }
    if (inputs.isEmpty) return;

    final result = buildAnimeDsl(inputs);
    if (!mounted) return;

    // 预览 DSL + 应用
    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('追剧 DSL 预览'),
        content: SizedBox(
          width: 340,
          height: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '起始 ${result.config.startDateIso} · '
                '${result.config.daysPerCycle} 天 · '
                '${result.config.slotsPerDay} 行 · '
                '${result.config.cycleCount} 周',
                style: ZenText.label,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ZenColors.sage.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ZenColors.hair),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      result.dsl,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('应用'),
          ),
        ],
      ),
    );
    if (apply != true) return;

    final store = ref.read(TimetableStore.provider.notifier);
    await store.updateConfig(
      startDateIso: result.config.startDateIso,
      cycleCount: result.config.cycleCount,
      daysPerCycle: result.config.daysPerCycle,
      slotsPerDay: result.config.slotsPerDay,
      isSchoolMode: false,
      isAnimeMode: true,
      leftLabelMode: 1,
      slotStartTimes: result.config.slotStartTimes,
      slotDurationMin: result.config.slotDurationMin,
    );
    await store.clearAllItems();
    final grouped = <String, List<CourseItem>>{};
    for (final course in result.items) {
      grouped.putIfAbsent(course.cellKey, () => []).add(course);
    }
    for (final entry in grouped.entries) {
      await store.upsertItems(entry.key, entry.value);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已应用追剧课表：${result.items.length} 部剧 · '
            '${result.config.cycleCount} 周',
          ),
        ),
      );
      Navigator.pop(context);
    }
  }

  // ──── 子组件：日期字段 ────
  // 通用模式：单个简单日期选择；学校模式：周数推算/自动对齐周一（fr #2）
  Widget _buildDateField() {
    if (!_isSchoolMode) {
      return _buildGeneralDateField();
    }
    return _buildSchoolDateField();
  }

  /// 通用模式：只一个日期入口，点按弹系统日期选择器，选哪天存哪天。
  Widget _buildGeneralDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () async {
            final current = DateTime.tryParse(_startDateController.text);
            final picked = await showDatePicker(
              context: context,
              initialDate: current ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
              helpText: '选择开始日期',
            );
            if (picked == null) return;
            final iso = picked.toIso8601String().split('T')[0];
            setState(() => _startDateController.text = iso);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: zenCard(),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 18, color: ZenColors.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('起始日期', style: ZenText.label),
                      const SizedBox(height: 2),
                      Text(
                        _startDateController.text,
                        style: ZenText.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: ZenColors.secondary, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 学校模式：原「周数推算 / 选日期自动对齐周一」双入口逻辑。
  Widget _buildSchoolDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () async {
            final date = await showDialog<String>(
              context: context,
              builder: (_) => const WeekCalculatorDialog(),
            );
            if (date != null) {
              setState(() => _startDateController.text = date);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: zenCard(),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 18, color: ZenColors.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('起始日期（周一）', style: ZenText.label),
                      const SizedBox(height: 2),
                      Text(
                        _startDateController.text,
                        style: ZenText.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: ZenColors.secondary, size: 18),
              ],
            ),
          ),
        ),
      ],
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
                    onChanged: (v) {
                      _slotStartTimes[i] = v.trim();
                    },
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

  /// 自定义模式：每节自定义文字输入（留空回退序号）
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
                    onChanged: (v) {
                      _slotLabels[i] = v.trim();
                    },
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

/// 追剧模式单行输入状态
class _AnimeInputRow {
  final TextEditingController titleCtrl = TextEditingController();
  final TextEditingController startDateCtrl = TextEditingController();
  final TextEditingController timeCtrl = TextEditingController();
  final TextEditingController episodesCtrl = TextEditingController();
  final TextEditingController durationCtrl = TextEditingController();
  int weekday = 1;

  void dispose() {
    titleCtrl.dispose();
    startDateCtrl.dispose();
    timeCtrl.dispose();
    episodesCtrl.dispose();
    durationCtrl.dispose();
  }
}

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
