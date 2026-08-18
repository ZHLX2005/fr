import 'dart:io';
import '../../../widgets/context_colors.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'recorder_controller.dart';
import 'const_recorder.dart';
import 'recorder_list_page.dart';
import 'waveform_view.dart';
import '../../../widgets/base/base_icon_button.dart';
import '../../../widgets/theme/zen_theme.dart';

/// 录音机 widget 桥接 —— 给桌面 widget 点击后的 autostart 用。
///
/// 用法同 [[notionImageHostKey]]:widget 入口(Handler / main)通过全局 key
/// 拿到当前 RecorderDemoPage 的 controller,直接调 [triggerRecordFromWidget]。
///
/// 注意: key 是 `<State<RecorderDemoPage>>` 类型,但 RecorderDemoPage 的 state
/// 必须是 public class 才能被外部引用;这里走 StatefulWidget 的内部约定
/// (external `notionImageHostKey` 同款),保持 API 对称。
final GlobalKey<State<RecorderDemoPage>> recorderPageKey =
    GlobalKey<State<RecorderDemoPage>>();

/// 桌面 widget / 通知点击入口 — 若当前页不是 RecorderDemoPage(冷启动),则
/// 标记一次 pending autostart,等 RecorderDemoPage mount 时再触发。
final ValueNotifier<bool> _pendingAutoStart = ValueNotifier(false);

/// 标志:widget 点击后是否需要自动开始录音。
/// `true` 时 RecorderDemoPage 第一次 mount → 自动调 controller.start()。
bool get recorderAutoStartPending => _pendingAutoStart.value;

/// 由桌面 widget click → MainActivity handleIntent →
/// WidgetChannel.notifyNavigateToRecorder → main.dart → FrNavigator →
/// RecorderHandler.build 时调用。
void markRecorderAutoStart() {
  _pendingAutoStart.value = true;
}

/// RecorderDemoPage mount 后由 RecorderDemoPageState 调一次,消费 pending flag
/// 并实际开始录音。
@visibleForTesting
Future<void> consumeRecorderAutoStart(RecorderController controller) async {
  if (!_pendingAutoStart.value) return;
  _pendingAutoStart.value = false;
  await controller.start();
}

/// 入口 Widget —— RecorderDemoPage.
///
/// 由 RecorderDemo.buildPage 创建,RecorderDemoPage 自身是 StatefulWidget 以便
/// initState 中消费 [recorderAutoStartPending]。
class RecorderDemoPage extends StatefulWidget {
  const RecorderDemoPage({super.key});

  @override
  State<RecorderDemoPage> createState() => _RecorderDemoPageState();
}

class _RecorderDemoPageState extends State<RecorderDemoPage> {
  late final RecorderController _controller;
  bool _autoStartConsumed = false;

  @override
  void initState() {
    super.initState();
    _controller = RecorderController();
    _controller.addListener(_onStateChanged);
    _controller.probePermission();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只消费一次 pending autostart;防止 widget rebuild 多次 start。
    if (!_autoStartConsumed && recorderAutoStartPending) {
      _autoStartConsumed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // 等 frame 渲染完再 start,UI 已 mount,permission probe 已就绪。
        await consumeRecorderAutoStart(_controller);
      });
    }
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onStateChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RecorderPageScaffold(
      controller: _controller,
      onStart: _controller.start,
      onPause: _controller.pause,
      onResume: _controller.resume,
      onStop: _controller.stop,
      onSave: () {
        final path = _controller.commitSave();
        if (!mounted) return;
        if (path != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text('${RecorderUiText.savedPrefix}$path'),
            ));
        }
      },
      onDiscard: () => _controller.discard(),
    );
  }
}

/// RecorderPageScaffold —— UI 装配层。
///
/// 拆出来便于:
/// 1. _RecorderDemoPageState 只管 controller 生命周期(资源)
/// 2. Scaffold 自身是 StatelessWidget,可独立预览 / 测试
/// 3. 桌面 widget autostart 调 controller.start() 时,UI 已就绪
class RecorderPageScaffold extends StatelessWidget {
  final RecorderController controller;
  final Future<bool> Function() onStart;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final Future<String?> Function() onStop;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  RecorderPageScaffold({
    super.key,
    required this.controller,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onSave,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    return zenPageScaffold(
      context: context,
  title: '录音机',
      actions: [
        ZenIconButton(
          icon: Icons.library_music_outlined,
          color: context.colors.text,
          variant: BaseIconButtonVariant.outline,
          size: 40,
          iconSize: 20,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RecorderListPage(controller: controller),
            ),
          ),
        ),
        SizedBox(width: 8),
      ],
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FormatInfoSection(),
              SizedBox(height: 16),
              _WaveformSection(controller: controller),
              SizedBox(height: 12),
              _LevelSection(controller: controller),
              SizedBox(height: 20),
              _ElapsedDisplay(listenable: controller.tickListenable),
              SizedBox(height: 24),
              _ControlPanel(
                controller: controller,
                onStart: onStart,
                onPause: onPause,
                onResume: onResume,
                onStop: onStop,
                onSave: onSave,
                onDiscard: onDiscard,
              ),
              SizedBox(height: 24),
              _LastRecordingCard(controller: controller),
              SizedBox(height: 16),
              _PermissionBanner(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── 子组件 ───────────────────────────

/// 工程信息面板:编码 / 采样率 / 比特率 / 声道。只读展示。
class _FormatInfoSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ZenSection(
      title: '工程信息',
      child: Text(
        'AAC LC · ${RecorderDefaults.sampleRate ~/ 1000}.1 kHz · '
        '${RecorderDefaults.bitRate ~/ 1000} kbps · '
        '${RecorderDefaults.numChannels == 1 ? "MONO" : "STEREO"}',
        style: ZenText.monoDigitSmall,
      ),
    );
  }
}

/// 波形 + 状态指示。
class _WaveformSection extends StatelessWidget {
  final RecorderController controller;
  const _WaveformSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isLive = controller.state == RecorderState.recording;
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: zenCardTheme(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ZenDot(),
                  SizedBox(width: 8),
                  Text(
                    isLive ? '正在录音' : _stateLabel(controller.state),
                    style: ZenText.label,
                  ),
                ],
              ),
              SizedBox(height: 8),
              WaveformView(
                dbListenable: controller.dbListenable,
                active: isLive,
              ),
            ],
          ),
        );
      },
    );
  }

  String _stateLabel(RecorderState s) => switch (s) {
        RecorderState.idle => '就绪',
        RecorderState.paused => '已暂停',
        RecorderState.stopped => '已停止',
        RecorderState.recording => '正在录音',
      };
}

/// 电平条。
class _LevelSection extends StatelessWidget {
  final RecorderController controller;
  const _LevelSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isLive = controller.state == RecorderState.recording;
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: zenCardTheme(context),
          child: LevelMeterView(
            dbListenable: controller.dbListenable,
            active: isLive,
          ),
        );
      },
    );
  }
}

/// 时长大字号显示。
class _ElapsedDisplay extends StatelessWidget {
  final ValueListenable<Duration> listenable;
  const _ElapsedDisplay({required this.listenable});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: listenable,
      builder: (context, value, _) {
        return Center(
          child: Text(
            formatTime(value.inSeconds),
            style: ZenText.monoDigitLarge,
          ),
        );
      },
    );
  }
}

/// 控制面板 —— 按状态切 hero + outline 组合。
class _ControlPanel extends StatelessWidget {
  final RecorderController controller;
  final Future<bool> Function() onStart;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final Future<String?> Function() onStop;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  const _ControlPanel({
    required this.controller,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onSave,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        switch (state) {
          case RecorderState.idle:
            return _CenterControls([
              _HeroRecord(onTap: onStart, icon: Icons.fiber_manual_record),
            ]);
          case RecorderState.recording:
            return _CenterControls([
              _OutlineBtn(
                  icon: Icons.pause, label: '暂停', color: context.colors.textMuted, onTap: onPause),
              SizedBox(width: 24),
              _HeroRecord(onTap: () async => onStop(), icon: Icons.stop),
            ]);
          case RecorderState.paused:
            return _CenterControls([
              _OutlineBtn(
                  icon: Icons.play_arrow, label: '继续', color: context.colors.accent, onTap: onResume),
              SizedBox(width: 24),
              _HeroRecord(onTap: () async => onStop(), icon: Icons.stop),
            ]);
          case RecorderState.stopped:
            return _CenterControls([
              _OutlineBtn(
                  icon: Icons.check, label: '保存', color: context.colors.accent, onTap: () async => onSave()),
              SizedBox(width: 24),
              _OutlineBtn(
                  icon: Icons.close, label: '放弃', color: context.colors.danger, onTap: () async => onDiscard()),
            ]);
        }
      },
    );
  }
}

class _CenterControls extends StatelessWidget {
  final List<Widget> children;
  const _CenterControls(this.children);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }
}

/// hero 大圆录音键(磁带符号)。
class _HeroRecord extends StatelessWidget {
  final Future Function() onTap;
  final IconData icon;
  const _HeroRecord({required this.onTap, required this.icon});

  @override
  Widget build(BuildContext context) {
    // 本地自绘 hero 键 —— ZenIconButton.hero 硬编码 sage,忽略 color 参数
    // (clocks/metronome/track 依赖该 sage 行为,不改 zen_theme)。
    // 这里直接复刻 hero 视觉规格(80×80 圆 + 0.4 alpha 阴影 + 48px 白图标),
    // 但把底色换成 context.colors.danger,使录音/停止键与状态指示器同色。
    return InkWell(
      onTap: () async => await onTap(),
      customBorder: CircleBorder(),
      child: Container(
        width: 80,
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.danger,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: context.colors.danger.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.onSurface, size: 48),
      ),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Future Function() onTap;
  const _OutlineBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async => await onTap(),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.outline),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            SizedBox(height: 4),
            Text(label, style: ZenText.label.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// 最近一次录音卡片。
class _LastRecordingCard extends StatelessWidget {
  final RecorderController controller;
  const _LastRecordingCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final path = controller.lastSavedPath;
        if (path == null) {
          return Text(
            RecorderUiText.noRecordingHint,
            style: ZenText.label,
          );
        }
        final sizeKb = (controller.lastFileSize / 1024).toStringAsFixed(1);
        final name = path.split(Platform.pathSeparator).last;
        return Container(
          padding: EdgeInsets.all(12),
          decoration: zenCardTheme(context),
          child: Row(
            children: [
              Icon(Icons.audiotrack, color: context.colors.accent),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZenText.body),
                    Text('$sizeKb KB', style: ZenText.monoDigitSmall),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 权限横幅:未授权时展示,提供授权按钮。
class _PermissionBanner extends StatelessWidget {
  final RecorderController controller;
  const _PermissionBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final status = controller.permissionStatus;
        if (status == RecorderPermissionStatus.granted ||
            status == RecorderPermissionStatus.unknown) {
          return SizedBox.shrink();
        }
        final isPermanent = status == RecorderPermissionStatus.permanentlyDenied;
        return Container(
          padding: EdgeInsets.all(12),
          decoration: zenCard(color: context.colors.danger.withValues(alpha: 0.06)),
          child: Row(
            children: [
              Icon(Icons.mic_off, color: context.colors.danger, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  isPermanent
                      ? RecorderUiText.permissionDeniedHint
                      : RecorderUiText.requestPermission,
                  style: ZenText.label.copyWith(color: context.colors.danger),
                ),
              ),
              OutlinedButton(
                style: zenButtonTheme(context,
                  foreground: context.colors.danger,
                  border: context.colors.danger,
                ),
                onPressed: () => controller.ensurePermission(),
                child: Text(isPermanent ? '打开设置' : '授权'),
              ),
            ],
          ),
        );
      },
    );
  }
}

