import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import '../lab_container.dart';

/// 麦克风录音可视化 Demo
class MicVisualizerDemo extends DemoPage {
  @override
  String get title => '麦克风录音';

  @override
  String get description => '实时麦克风录音可视化';

  @override
  Widget buildPage(BuildContext context) {
    return const _MicVisualizerPage();
  }
}

class _MicVisualizerPage extends StatefulWidget {
  const _MicVisualizerPage();

  @override
  State<_MicVisualizerPage> createState() => _MicVisualizerPageState();
}

class _MicVisualizerPageState extends State<_MicVisualizerPage> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _hasPermission = false;
  String? _errorMessage;

  // 波形数据
  final List<double> _waveData = List.generate(50, (i) => 0.1);
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  Timer? _simulationTimer;

  // 录音时长
  int _recordingSeconds = 0;
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _startSimulation();
  }

  Future<void> _checkPermission() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (mounted) {
        setState(() {
          _hasPermission = hasPermission;
          if (!hasPermission) {
            _errorMessage = '麦克风权限被拒绝';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '检查权限失败: $e';
        });
      }
    }
  }

  void _startSimulation() {
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (mounted) {
        setState(() {
          // 无录音时显示静态波形
          for (int i = 0; i < _waveData.length; i++) {
            final target = _isRecording ? 0.3 + math.Random().nextDouble() * 0.7 : 0.1;
            _waveData[i] = _waveData[i] + (target - _waveData[i]) * 0.3;
          }
        });
      }
    });
  }

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

      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      );

      await _recorder.start(config, path: 'recording.webm');

      // 监听音量变化
      _amplitudeSubscription = _recorder.onAmplitudeChanged(
        const Duration(milliseconds: 50),
      ).listen((amplitude) {
        if (mounted) {
          _updateWaveFromAmplitude(amplitude.current);
        }
      });

      // 开始计时
      _recordingSeconds = 0;
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && _isRecording) {
          setState(() {
            _recordingSeconds++;
          });
        }
      });

      setState(() {
        _isRecording = true;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '录音失败: $e';
      });
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
      setState(() {
        _errorMessage = '停止录音失败: $e';
        _isRecording = false;
      });
    }
  }

  void _updateWaveFromAmplitude(double amplitude) {
    // amplitude 范围大约是 -160 到 0 dB
    // 转换为 0-1 的波形数据
    final normalizedAmplitude = (amplitude + 60) / 60; // -60dB 为最小值
    final clampedAmplitude = normalizedAmplitude.clamp(0.0, 1.0);

    // 更新波形数据，向左移动
    for (int i = 0; i < _waveData.length - 1; i++) {
      _waveData[i] = _waveData[i + 1];
    }
    // 最后一个位置使用当前音量
    _waveData[_waveData.length - 1] = clampedAmplitude;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  '麦克风录音',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _checkPermission,
                      tooltip: '刷新权限',
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
                    _isRecording ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                  ],
                ),
              ),
              child: _buildVisualizer(),
            ),
          ),
          // 状态信息
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
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
                // 录音状态
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRecording ? Colors.red : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isRecording ? '录音中' : '等待录音',
                      style: TextStyle(
                        color: _isRecording ? Colors.red : Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_isRecording) ...[
                      const SizedBox(width: 16),
                      Icon(Icons.timer, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(_recordingSeconds),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
                // 录音按钮
                GestureDetector(
                  onTap: _hasPermission ? _toggleRecording : _checkPermission,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording ? Colors.red : theme.colorScheme.primary,
                      boxShadow: [
                        BoxShadow(
                          color: (_isRecording ? Colors.red : theme.colorScheme.primary)
                              .withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _hasPermission
                      ? (_isRecording ? '点击停止录音' : '点击开始录音')
                      : '点击授权麦克风',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  '对着麦克风说话或播放音乐查看波形',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualizer() {
    return _MicWaveVisualizer(waveData: _waveData, isRecording: _isRecording);
  }
}

/// 麦克风波形可视化
class _MicWaveVisualizer extends StatelessWidget {
  final List<double> waveData;
  final bool isRecording;

  const _MicWaveVisualizer({required this.waveData, required this.isRecording});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _MicWavePainter(
            waveData: waveData,
            isRecording: isRecording,
          ),
        );
      },
    );
  }
}

class _MicWavePainter extends CustomPainter {
  final List<double> waveData;
  final bool isRecording;

  _MicWavePainter({required this.waveData, required this.isRecording});

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    // 绘制中心线
    final centerLinePaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), centerLinePaint);

    // 绘制波形
    final path = Path();
    final fillPath = Path();

    final barWidth = size.width / waveData.length;

    for (int i = 0; i < waveData.length; i++) {
      final x = i * barWidth + barWidth / 2;
      final amplitude = waveData[i] * size.height * 0.4;

      if (i == 0) {
        path.moveTo(x, centerY - amplitude);
        fillPath.moveTo(x, centerY);
        fillPath.lineTo(x, centerY - amplitude);
      } else {
        path.lineTo(x, centerY - amplitude);
        fillPath.lineTo(x, centerY - amplitude);
      }
    }

    // 完成填充路径
    for (int i = waveData.length - 1; i >= 0; i--) {
      final x = i * barWidth + barWidth / 2;
      final amplitude = waveData[i] * size.height * 0.4;
      fillPath.lineTo(x, centerY + amplitude);
    }
    fillPath.close();

    // 填充波形
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isRecording
            ? [Colors.red.withOpacity(0.6), Colors.red.withOpacity(0.1)]
            : [Colors.blue.withOpacity(0.6), Colors.blue.withOpacity(0.1)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    // 绘制波形线
    final strokePaint = Paint()
      ..color = isRecording ? Colors.red : Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, strokePaint);

    // 绘制下部分波形（镜像）
    final mirrorPath = Path();
    for (int i = 0; i < waveData.length; i++) {
      final x = i * barWidth + barWidth / 2;
      final amplitude = waveData[i] * size.height * 0.4;

      if (i == 0) {
        mirrorPath.moveTo(x, centerY + amplitude);
      } else {
        mirrorPath.lineTo(x, centerY + amplitude);
      }
    }

    final mirrorStrokePaint = Paint()
      ..color = (isRecording ? Colors.red : Colors.blue).withOpacity(0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(mirrorPath, mirrorStrokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

void registerMicVisualizerDemo() {
  demoRegistry.register(MicVisualizerDemo());
}
