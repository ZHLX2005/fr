import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../lab_container.dart';
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

class _MetronomePage extends StatelessWidget {
  const _MetronomePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('节拍器'),
        backgroundColor: Colors.grey[50],
        elevation: 0,
        centerTitle: true,
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
          currentBeat: controller.currentBeatIndex,
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
                currentBeat: controller.currentBeatIndex,
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
                    style: TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  Text(
                    'BPM',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
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
            activeTrackColor: Theme.of(context).primaryColor,
            inactiveTrackColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
            thumbColor: Theme.of(context).primaryColor,
            overlayColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
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
                      ? Theme.of(context).primaryColor
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '$bpm',
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[700],
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
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
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
          onPressed: controller.isPlaying ? controller.pause : null,
          icon: Icon(
            Icons.pause_rounded,
            color: controller.isPlaying ? Colors.grey[700] : Colors.grey[300],
            size: 32,
          ),
        ),

        const SizedBox(width: 16),

        // 播放/停止按钮
        PlayControlButton(
          isPlaying: controller.isPlaying,
          onPressed: controller.togglePlay,
        ),

        const SizedBox(width: 16),

        // 重置 Tap Tempo
        IconButton(
          onPressed: controller.resetTapTempo,
          icon: Icon(
            Icons.refresh_rounded,
            color: Colors.grey[700],
            size: 32,
          ),
          tooltip: '重置 Tap Tempo',
        ),
      ],
    );
  }

  /// 重音图例
  Widget _buildAccentLegend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '节拍强度',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
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
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  /// 显示 BPM 选择器弹窗
  void _showBpmPicker(BuildContext context, MetronomeController controller) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
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
