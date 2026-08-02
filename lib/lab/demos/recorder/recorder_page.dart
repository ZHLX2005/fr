import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'recorder_controller.dart';
import 'const_recorder.dart';

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

  const RecorderPageScaffold({
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('录音机'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 500;
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 32,
                ),
                child: isWide
                    ? _buildWideLayout(context)
                    : _buildNarrowLayout(context),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNarrowLayout(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ElapsedDisplay(listenable: controller.tickListenable),
        const SizedBox(height: 32),
        _WaveformPlaceholder(),
        const SizedBox(height: 32),
        _PermissionBanner(controller: controller),
        const SizedBox(height: 16),
        _ControlPanel(
          controller: controller,
          onStart: onStart,
          onPause: onPause,
          onResume: onResume,
          onStop: onStop,
          onSave: onSave,
          onDiscard: onDiscard,
        ),
        const SizedBox(height: 24),
        _LastRecordingCard(controller: controller),
      ],
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ElapsedDisplay(listenable: controller.tickListenable),
              const SizedBox(height: 24),
              _WaveformPlaceholder(),
            ],
          ),
        ),
        const SizedBox(width: 32),
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PermissionBanner(controller: controller),
              const SizedBox(height: 16),
              _ControlPanel(
                controller: controller,
                onStart: onStart,
                onPause: onPause,
                onResume: onResume,
                onStop: onStop,
                onSave: onSave,
                onDiscard: onDiscard,
              ),
              const SizedBox(height: 24),
              _LastRecordingCard(controller: controller),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────── 子组件 ───────────────────────────

/// 录音时长大字号显示(订阅 tickListenable,1Hz rebuild 但自身很轻)。
class _ElapsedDisplay extends StatelessWidget {
  final ValueListenable<Duration> listenable;
  const _ElapsedDisplay({required this.listenable});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: listenable,
      builder: (context, value, _) {
        return Text(
          _format(value),
          style: const TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.w300,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        );
      },
    );
  }

  static String _format(Duration d) {
    final total = d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${mm.padLeft(2, '0')}:$ss';
    return '$mm:$ss';
  }
}

/// 简易波形占位 —— v1 不画真实波形,只用一个脉冲圆环表示录音中。
/// v2 可接 AudioRecorder.onAmplitudeChanged 取 dBFS 实时绘制。
class _WaveformPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: Center(
        child: AnimatedBuilder(
          animation: AlwaysStoppedAnimation(0),
          builder: (context, _) {
            return Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.redAccent.withValues(alpha: 0.2),
                border: Border.all(color: Colors.redAccent, width: 2),
              ),
              child: const Icon(Icons.mic, color: Colors.redAccent, size: 32),
            );
          },
        ),
      ),
    );
  }
}

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
          return const SizedBox.shrink();
        }
        final isPermanent = status == RecorderPermissionStatus.permanentlyDenied;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isPermanent
                    ? RecorderUiText.permissionDeniedHint
                    : RecorderUiText.requestPermission,
                style: TextStyle(color: Colors.orange.shade900),
              ),
              const SizedBox(height: 8),
              TextButton(
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
        final List<Widget> buttons;
        switch (state) {
          case RecorderState.idle:
            buttons = [
              _RecordButton(
                icon: Icons.fiber_manual_record,
                label: RecorderUiText.start,
                color: Colors.redAccent,
                onPressed: onStart,
              ),
            ];
            break;
          case RecorderState.recording:
            buttons = [
              _RecordButton(
                icon: Icons.pause,
                label: RecorderUiText.pause,
                color: Colors.orange,
                onPressed: onPause,
              ),
              _RecordButton(
                icon: Icons.stop,
                label: RecorderUiText.stop,
                color: Colors.grey,
                onPressed: onStop,
              ),
            ];
            break;
          case RecorderState.paused:
            buttons = [
              _RecordButton(
                icon: Icons.play_arrow,
                label: RecorderUiText.resume,
                color: Colors.redAccent,
                onPressed: onResume,
              ),
              _RecordButton(
                icon: Icons.stop,
                label: RecorderUiText.stop,
                color: Colors.grey,
                onPressed: onStop,
              ),
            ];
            break;
          case RecorderState.stopped:
            buttons = [
              _RecordButton(
                icon: Icons.save,
                label: RecorderUiText.save,
                color: Colors.green,
                onPressed: () async => onSave(),
              ),
              _RecordButton(
                icon: Icons.delete_outline,
                label: RecorderUiText.discard,
                color: Colors.grey,
                onPressed: () async => onDiscard(),
              ),
            ];
            break;
        }
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: buttons,
        );
      },
    );
  }
}

class _RecordButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Future Function() onPressed;

  const _RecordButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () async => await onPressed(),
      icon: Icon(icon, color: color),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    );
  }
}

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
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          );
        }
        final sizeKb = (controller.lastFileSize / 1024).toStringAsFixed(1);
        final name = path.split(Platform.pathSeparator).last;
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.audiotrack),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('$sizeKb KB'),
          ),
        );
      },
    );
  }
}

