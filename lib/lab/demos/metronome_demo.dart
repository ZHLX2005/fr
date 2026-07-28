import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lab_container.dart';
import 'clock/widgets/zen_theme.dart' show ZenColors, ZenText, zenCard;
import 'metronome/const_metronome.dart';
import 'metronome/metronome_controller.dart';
import 'metronome/metronome_widgets.dart';

/// 节拍器 Demo
class MetronomeDemo extends DemoPage {
  @override
  String get title => '节拍器';

  @override
  String get slug => 'metronome';

  @override
  String get description => '专业节拍器，支持滚轮调速和多种节拍模式';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MetronomeController(),
      child: const _MetronomePage(),
    );
  }
}

class _MetronomePage extends StatefulWidget {
  const _MetronomePage();

  @override
  State<_MetronomePage> createState() => _MetronomePageState();
}

class _MetronomePageState extends State<_MetronomePage> {
  /// Used to avoid redundant saves after a user-initiated change.
  bool _restoringSlots = false;

  // Sound profile labels for the dropdown picker.
  static const _soundLabels = ['合成 (默认)', '木鱼'];
  // Maps back: index → sound id passed to the controller.
  static const _soundIds = [
    MetronomeController.soundSynth,
    MetronomeController.soundWoodfish,
  ];

  MetronomeController? _boundController;

  void _onError() {
    final err = _boundController?.errorNotifier.value;
    if (err == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('节拍器出错：$err')));
    _boundController!.errorNotifier.value = null;
  }

  Future<void> _restoreSoundSlots(MetronomeController c) async {
    if (_restoringSlots) return;
    _restoringSlots = true;
    final prefs = await SharedPreferences.getInstance();
    for (var level = 0; level < 3; level++) {
      final saved = prefs.getInt(_spKey(level)) ?? 0;
      if (saved != 0) {
        unawaited(c.setSoundForLevel(level, saved));
      }
    }
  }

  static String _spKey(int level) => 'metronome_slot_$level';

  Future<void> _onSoundChanged(
    MetronomeController c,
    int level,
    int selectedIndex,
  ) async {
    final soundId = _soundIds[selectedIndex];
    final ok = await c.setSoundForLevel(level, soundId);
    if (ok && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_spKey(level), soundId);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = context.read<MetronomeController>();
    if (identical(_boundController, c)) return;
    _boundController?.errorNotifier.removeListener(_onError);
    _boundController = c;
    _boundController!.errorNotifier.addListener(_onError);
    // Restore saved sound selections once.
    _restoreSoundSlots(c);
  }

  @override
  void dispose() {
    _boundController?.errorNotifier.removeListener(_onError);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZenColors.bg,
      appBar: AppBar(
        title: const Text('节拍器', style: ZenText.title),
        backgroundColor: ZenColors.bg,
        elevation: 0,
      ),
      body: SafeArea(
        child: Consumer<MetronomeController>(
          builder: (context, controller, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 500;
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 32,
                    ),
                    child: isWide
                        ? _buildWideLayout(context, controller)
                        : _buildNarrowLayout(context, controller),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// 窄屏布局（手机竖屏）
  Widget _buildNarrowLayout(BuildContext context, MetronomeController controller) {
    return Column(
      children: [
        // 速度标记
        TempoMarking(bpm: controller.bpm),
        const SizedBox(height: 8),

        // 节拍指示器
        BeatIndicator(
          beatCount: controller.beatPattern.beatsPerMeasure,
          currentBeatListenable: controller.currentBeatNotifier,
          isPlaying: controller.isPlaying,
          beatPattern: controller.beatPattern,
        ),
        const SizedBox(height: 24),

        // BPM 显示与滚轮
        _buildBpmSection(context, controller),
        const SizedBox(height: 24),

        // 拍号选择
        _buildTimeSignatureSection(context, controller),
        const SizedBox(height: 24),

        // 控制按钮
        _buildControlSection(context, controller),
        const SizedBox(height: 24),

        // Tap Tempo
        TapTempoButton(onTap: controller.tap),
        const SizedBox(height: 16),

        // 重音模式说明
        _buildAccentLegend(),
        const SizedBox(height: 16),

        // 音色配置
        _buildSoundSection(context, controller),
        const SizedBox(height: 16),
      ],
    );
  }

  /// 宽屏布局（平板横屏）
  Widget _buildWideLayout(BuildContext context, MetronomeController controller) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 左侧 - 节拍指示器和摆锤
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TempoMarking(bpm: controller.bpm),
              const SizedBox(height: 16),
              BeatIndicator(
                beatCount: controller.beatPattern.beatsPerMeasure,
                currentBeatListenable: controller.currentBeatNotifier,
                isPlaying: controller.isPlaying,
                beatPattern: controller.beatPattern,
              ),
              const SizedBox(height: 16),
              PendulumAnimation(
                bpm: controller.bpm,
                isPlaying: controller.isPlaying,
              ),
            ],
          ),
        ),

        const SizedBox(width: 32),

        // 右侧 - 控制面板
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildBpmSection(context, controller),
              const SizedBox(height: 24),
              _buildTimeSignatureSection(context, controller),
              const SizedBox(height: 24),
              _buildControlSection(context, controller),
              const SizedBox(height: 16),
              TapTempoButton(onTap: controller.tap),
              const SizedBox(height: 16),
              _buildSoundSection(context, controller),
            ],
          ),
        ),
      ],
    );
  }

  /// BPM 区域
  Widget _buildBpmSection(BuildContext context, MetronomeController controller) {
    return Column(
      children: [
        // BPM 大数字显示
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            BpmAdjustButton(
              icon: Icons.remove,
              onPressed: controller.decrementBpm,
            ),
            const SizedBox(width: 24),
            GestureDetector(
              onTap: () => _showBpmPicker(context, controller),
              child: Column(
                children: [
                  Text(
                    controller.bpm.toString(),
                    style: ZenText.title.copyWith(
                      fontSize: 64,
                      color: ZenColors.sage,
                    ),
                  ),
                  Text(
                    'BPM',
                    style: ZenText.label,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            BpmAdjustButton(
              icon: Icons.add,
              onPressed: controller.incrementBpm,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // BPM 滑块
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: ZenColors.sage,
            inactiveTrackColor: ZenColors.sage.withValues(alpha: 0.2),
            thumbColor: ZenColors.sage,
            overlayColor: ZenColors.sage.withValues(alpha: 0.1),
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
          ),
          child: Slider(
            value: controller.bpm.toDouble(),
            min: MetronomeDefaults.minBpm.toDouble(),
            max: MetronomeDefaults.maxBpm.toDouble(),
            onChanged: (value) => controller.setBpm(value.round()),
          ),
        ),

        // BPM 快捷按钮
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [60, 80, 100, 120, 140, 160, 180, 200].map((bpm) {
            final isSelected = controller.bpm == bpm;
            return GestureDetector(
              onTap: () => controller.setBpm(bpm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? ZenColors.sage
                      : ZenColors.hair,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '$bpm',
                  style: TextStyle(
                    color: isSelected ? Colors.white : ZenColors.ink,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 拍号选择区域
  Widget _buildTimeSignatureSection(
    BuildContext context,
    MetronomeController controller,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '节拍模式',
            style: ZenText.label,
          ),
        ),
        TimeSignaturePicker(
          patterns: MetronomePresets.patterns,
          selectedPattern: controller.beatPattern,
          onPatternSelected: controller.setBeatPattern,
        ),
      ],
    );
  }

  /// 控制区域
  Widget _buildControlSection(BuildContext context, MetronomeController controller) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 暂停按钮（可选）
        IconButton(
          onPressed: controller.isPlaying ? () => controller.pause() : null,
          icon: Icon(
            Icons.pause_rounded,
            color: controller.isPlaying ? ZenColors.ink : ZenColors.hair,
            size: 32,
          ),
        ),

        const SizedBox(width: 16),

        // 播放/停止按钮
        PlayControlButton(
          isPlaying: controller.isPlaying,
          onPressed: () => controller.togglePlay(),
        ),

        const SizedBox(width: 16),

        // 重置 Tap Tempo
        IconButton(
          onPressed: controller.resetTapTempo,
          icon: Icon(
            Icons.refresh_rounded,
            color: ZenColors.ink,
            size: 32,
          ),
          tooltip: '重置 Tap Tempo',
        ),
      ],
    );
  }

  /// 音色配置区域
  Widget _buildSoundSection(BuildContext context, MetronomeController controller) {
    // Map from display order (accent→medium→weak) to C++ slot indices
    // (0=weak, 1=medium, 2=accent).  The UI shows 强拍 first but its C++
    // slot is 2, so we translate here.
    const uiToCppSlot = [2, 1, 0]; // accent→slot2, medium→slot1, weak→slot0

    final accentColors = [
      AccentColor.getColor(AccentLevel.accent),
      AccentColor.getColor(AccentLevel.medium),
      AccentColor.getColor(AccentLevel.weak),
    ];
    final labels = const ['强拍（重音）', '次强拍', '弱拍'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: zenCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '音色',
            style: ZenText.label,
          ),
          const SizedBox(height: 8),
          for (int displayIdx = 0; displayIdx < 3; displayIdx++) ...[
            if (displayIdx > 0) const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColors[displayIdx],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  labels[displayIdx],
                  style: TextStyle(
                    fontSize: 13,
                    color: ZenColors.ink,
                  ),
                ),
                const Spacer(),
                DropdownButton<int>(
                  value: controller.soundForLevel(uiToCppSlot[displayIdx]),
                  underline: const SizedBox(),
                  style: TextStyle(
                    fontSize: 13,
                    color: ZenColors.sage,
                  ),
                  items: _soundIds.asMap().entries.map((e) {
                    return DropdownMenuItem(
                      value: e.value,
                      child: Text(_soundLabels[e.key]),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      _onSoundChanged(controller, uiToCppSlot[displayIdx], v);
                    }
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '选择「木鱼」后该档位使用真实采样，否则使用合成音色。',
            style: TextStyle(
              fontSize: 11,
              color: ZenColors.secondary,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildAccentLegend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: zenCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '节拍强度',
            style: ZenText.label,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildLegendItem(
                color: AccentColor.getColor(AccentLevel.accent),
                label: '强拍',
              ),
              _buildLegendItem(
                color: AccentColor.getColor(AccentLevel.medium),
                label: '次强',
              ),
              _buildLegendItem(
                color: AccentColor.getColor(AccentLevel.weak),
                label: '弱拍',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: ZenColors.secondary,
          ),
        ),
      ],
    );
  }

  /// 显示 BPM 选择器弹窗
  void _showBpmPicker(BuildContext context, MetronomeController controller) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ZenColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '选择 BPM',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BpmWheelPicker(
                value: controller.bpm,
                onChanged: (value) {
                  controller.setBpm(value);
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ZenColors.sage,
                  side: BorderSide(
                    color: ZenColors.sage.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('确定'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 注册函数
void registerMetronomeDemo() {
  demoRegistry.register(MetronomeDemo());
}
