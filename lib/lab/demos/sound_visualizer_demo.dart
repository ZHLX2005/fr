import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../lab_container.dart';

/// 声音可视化 Demo - 合并音频播放和麦克风录音
class SoundVisualizerDemo extends DemoPage {
  @override
  String get title => '声音可视化';

  @override
  String get description => '音频播放与麦克风录音实时可视化';

  @override
  Widget buildPage(BuildContext context) {
    return const _SoundVisualizerPage();
  }
}

class _SoundVisualizerPage extends StatefulWidget {
  const _SoundVisualizerPage();

  @override
  State<_SoundVisualizerPage> createState() => _SoundVisualizerPageState();
}

class _SoundVisualizerPageState extends State<_SoundVisualizerPage>
    with TickerProviderStateMixin {
  // 录音相关
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _hasPermission = false;

  // 播放相关
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

  // 共享波形数据
  final List<double> _waveData = List.generate(50, (i) => 0.1);

  // 监听
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  Timer? _simulationTimer;

  // 录音时长
  int _recordingSeconds = 0;
  Timer? _durationTimer;

  // 当前模式: 0=播放, 1=录音
  int _mode = 0;
  int _visualizerStyle = 0; // 0: 柱状 1: 波浪 2: 圆形

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _startSimulation();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          if (!_isPlaying) {
            _mode = 0;
          }
        });
      }
    });
  }

  Future<void> _checkPermission() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (mounted) {
        setState(() {
          _hasPermission = hasPermission;
        });
      }
    } catch (e) {
      debugPrint('检查权限失败: $e');
    }
  }

  void _startSimulation() {
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (mounted) {
        setState(() {
          // 无活动时显示静态波形
          final bool isActive = _isRecording || _isPlaying;
          for (int i = 0; i < _waveData.length; i++) {
            final target = isActive ? 0.3 + math.Random().nextDouble() * 0.7 : 0.1;
            _waveData[i] = _waveData[i] + (target - _waveData[i]) * 0.3;
          }
        });
      }
    });
  }

  // 录音控制
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!_hasPermission) {
        await _checkPermission();
        if (!_hasPermission) return;
      }

      String path;
      if (kIsWeb) {
        path = 'recording.webm';
      } else {
        final dir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        path = '${dir.path}/recording_$timestamp.m4a';
      }

      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      );

      await _recorder.start(config, path: path);

      _amplitudeSubscription = _recorder.onAmplitudeChanged(
        const Duration(milliseconds: 50),
      ).listen((amplitude) {
        if (mounted) {
          _updateWaveFromAmplitude(amplitude.current);
        }
      });

      _recordingSeconds = 0;
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && _isRecording) {
          setState(() {
            _recordingSeconds++;
          });
        }
      });

      // 停止播放
      if (_isPlaying) {
        await _audioPlayer.stop();
      }

      setState(() {
        _isRecording = true;
        _mode = 1;
      });
    } catch (e) {
      debugPrint('录音失败: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      _durationTimer?.cancel();
      _durationTimer = null;

      await _recorder.stop();

      setState(() {
        _isRecording = false;
      });
    } catch (e) {
      debugPrint('停止录音失败: $e');
      setState(() {
        _isRecording = false;
      });
    }
  }

  void _updateWaveFromAmplitude(double amplitude) {
    final normalizedAmplitude = (amplitude + 60) / 60;
    final clampedAmplitude = normalizedAmplitude.clamp(0.0, 1.0);

    for (int i = 0; i < _waveData.length - 1; i++) {
      _waveData[i] = _waveData[i + 1];
    }
    _waveData[_waveData.length - 1] = clampedAmplitude;
  }

  // 播放控制
  void _playDemoSound() async {
    try {
      if (_isRecording) {
        await _stopRecording();
      }

      await _audioPlayer.play(UrlSource(
        'https://www.soundjay.com/misc/sounds/bell-ringing-05.mp3',
      ));

      setState(() {
        _mode = 0;
      });
    } catch (e) {
      debugPrint('播放失败: $e');
    }
  }

  void _playDemoLoop() async {
    try {
      if (_isRecording) {
        await _stopRecording();
      }

      await _audioPlayer.play(UrlSource(
        'https://www.soundjay.com/misc/sounds/digital-ring-07.mp3',
      ));

      setState(() {
        _mode = 0;
      });
    } catch (e) {
      debugPrint('播放失败: $e');
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _amplitudeSubscription?.cancel();
    _simulationTimer?.cancel();
    _durationTimer?.cancel();
    _recorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isActive = _isRecording || _isPlaying;
    final activeColor = _isRecording ? Colors.red : (_isPlaying ? Colors.blue : Colors.grey);

    return SafeArea(
      child: Column(
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '声音可视化',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () {
                        setState(() {
                          _visualizerStyle = (_visualizerStyle + 1) % 3;
                        });
                      },
                      tooltip: '切换样式',
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 可视化区域
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.surface,
                    activeColor.withOpacity(0.1),
                  ],
                ),
              ),
              child: _buildVisualizer(),
            ),
          ),
          // 控制面板
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                // 状态指示
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: activeColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isRecording
                          ? '录音中 ${_formatDuration(_recordingSeconds)}'
                          : (_isPlaying ? '播放中' : '等待输入'),
                      style: TextStyle(
                        color: activeColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 模式选择
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ModeButton(
                      icon: Icons.mic,
                      label: '麦克风录音',
                      isSelected: _mode == 1,
                      onTap: _toggleRecording,
                    ),
                    _ModeButton(
                      icon: Icons.play_arrow,
                      label: '播放音频',
                      isSelected: _mode == 0 && _isPlaying,
                      onTap: _playDemoSound,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // 控制按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 录音按钮
                    FloatingActionButton(
                      heroTag: 'mic',
                      onPressed: _toggleRecording,
                      backgroundColor: _isRecording ? Colors.red : theme.colorScheme.primary,
                      child: Icon(_isRecording ? Icons.stop : Icons.mic),
                    ),
                    const SizedBox(width: 24),
                    // 播放按钮
                    FloatingActionButton(
                      heroTag: 'play',
                      onPressed: _isPlaying ? () => _audioPlayer.stop() : _playDemoSound,
                      backgroundColor: _isPlaying ? Colors.red : Colors.blue,
                      child: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                    ),
                    const SizedBox(width: 24),
                    // 循环播放按钮
                    FloatingActionButton(
                      heroTag: 'loop',
                      onPressed: _playDemoLoop,
                      backgroundColor: Colors.orange,
                      child: const Icon(Icons.loop),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 样式选择
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StyleButton(
                      icon: Icons.bar_chart,
                      label: '柱状',
                      isSelected: _visualizerStyle == 0,
                      onTap: () => setState(() => _visualizerStyle = 0),
                    ),
                    _StyleButton(
                      icon: Icons.waves,
                      label: '波浪',
                      isSelected: _visualizerStyle == 1,
                      onTap: () => setState(() => _visualizerStyle = 1),
                    ),
                    _StyleButton(
                      icon: Icons.radio_button_checked,
                      label: '圆形',
                      isSelected: _visualizerStyle == 2,
                      onTap: () => setState(() => _visualizerStyle = 2),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualizer() {
    switch (_visualizerStyle) {
      case 0:
        return _BarVisualizer(waveData: _waveData);
      case 1:
        return _WaveVisualizer(waveData: _waveData);
      case 2:
        return _CircleVisualizer(waveData: _waveData);
      default:
        return _BarVisualizer(waveData: _waveData);
    }
  }
}

/// 模式选择按钮
class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
              : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 样式选择按钮
class _StyleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _StyleButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
              : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 柱状可视化
class _BarVisualizer extends StatelessWidget {
  final List<double> waveData;

  const _BarVisualizer({required this.waveData});

  @override
  Widget build(BuildContext context) {
    final colors = [Colors.purple, Colors.blue, Colors.cyan, Colors.green, Colors.yellow, Colors.orange, Colors.red];

    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.maxWidth / waveData.length - 4;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(waveData.length, (index) {
            final height = waveData[index] * constraints.maxHeight * 0.8;
            final colorIndex = (index / waveData.length * colors.length).floor();

            return AnimatedContainer(
              duration: const Duration(milliseconds: 50),
              width: barWidth.clamp(2.0, 12.0),
              height: height.clamp(4.0, constraints.maxHeight * 0.8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(barWidth / 2),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    colors[colorIndex % colors.length],
                    colors[(colorIndex + 1) % colors.length].withOpacity(0.5),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// 波浪可视化
class _WaveVisualizer extends StatelessWidget {
  final List<double> waveData;

  const _WaveVisualizer({required this.waveData});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _WavePainter(waveData: waveData),
    );
  }
}

class _WavePainter extends CustomPainter {
  final List<double> waveData;

  _WavePainter({required this.waveData});

  @override
  void paint(Canvas canvas, Size size) {
    _drawWave(canvas, size, 0.8, Colors.blue.withOpacity(0.5), 2);
    _drawWave(canvas, size, 0.6, Colors.purple.withOpacity(0.4), 3);
    _drawWave(canvas, size, 0.4, Colors.cyan.withOpacity(0.3), 4);
  }

  void _drawWave(Canvas canvas, Size size, double amplitude, Color color, double phase) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final midY = size.height / 2;

    for (int i = 0; i < waveData.length; i++) {
      final x = (i / waveData.length) * size.width;
      final y = midY + math.sin((i / waveData.length) * math.pi * 2 + phase) *
                waveData[i] * amplitude * size.height * 0.4;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 圆形可视化
class _CircleVisualizer extends StatelessWidget {
  final List<double> waveData;

  const _CircleVisualizer({required this.waveData});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CustomPaint(
        size: const Size(250, 250),
        painter: _CircleWavePainter(waveData: waveData),
      ),
    );
  }
}

class _CircleWavePainter extends CustomPainter {
  final List<double> waveData;

  _CircleWavePainter({required this.waveData});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 4;

    for (int ring = 0; ring < 3; ring++) {
      final ringRadius = baseRadius + ring * 30.0;
      final path = Path();

      for (int i = 0; i <= waveData.length; i++) {
        final index = i % waveData.length;
        final angle = (index / waveData.length) * math.pi * 2 - math.pi / 2;
        final radius = ringRadius + waveData[index] * 40 * (ring + 1) / 3;

        final x = center.dx + radius * math.cos(angle);
        final y = center.dy + radius * math.sin(angle);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();

      final colors = [Colors.blue, Colors.purple, Colors.cyan];
      final paint = Paint()
        ..color = colors[ring].withOpacity(0.3 - ring * 0.1)
        ..style = PaintingStyle.fill;

      canvas.drawPath(path, paint);

      final strokePaint = Paint()
        ..color = colors[ring].withOpacity(0.6)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      canvas.drawPath(path, strokePaint);
    }

    final centerPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.blue, Colors.purple],
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius * 0.8));

    canvas.drawCircle(center, baseRadius * 0.6, centerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

void registerSoundVisualizerDemo() {
  demoRegistry.register(SoundVisualizerDemo());
}
