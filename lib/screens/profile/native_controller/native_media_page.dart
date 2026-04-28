import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../services/media_service.dart';
import '../../../services/audio_recording_service.dart';

/// 原生媒体功能测试页面
/// 用于在Web和移动端验证摄像头、图库、麦克风等原生功能
class NativeMediaPage extends StatefulWidget {
  const NativeMediaPage({super.key});

  @override
  State<NativeMediaPage> createState() => _NativeMediaPageState();
}

class _NativeMediaPageState extends State<NativeMediaPage> {
  String _selectedImagePath = '';
  String _testResult = '';
  MediaCapability? _capability;
  bool _isLoading = false;

  // 录音相关
  final AudioRecordingService _audioService = AudioRecordingService();
  bool _isAudioRecording = false;
  String? _recordedAudioPath;
  int _recordingDuration = 0;

  // 音频播放相关
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _checkCapabilities();

    // 监听音频播放状态
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _checkCapabilities() async {
    setState(() {
      _isLoading = true;
    });

    final capability = await MediaService.checkWebCapabilities();

    setState(() {
      _capability = capability;
      _isLoading = false;
      _testResult = capability.toString();
    });
  }

  Future<void> _pickFromGallery() async {
    setState(() {
      _isLoading = true;
      _testResult = '正在打开图库...';
    });

    try {
      final path = await MediaService.pickImageFromGallery();
      if (path != null) {
        setState(() {
          _selectedImagePath = path;
          _testResult =
              '成功选择图片\n\n路径: ${path.length > 100 ? path.substring(0, 100) + '...' : path}\n\n'
              '图片格式: ${kIsWeb ? "Base64 (Web)" : "文件路径"}';
        });
      } else {
        setState(() {
          _testResult = '未选择图片';
        });
      }
    } catch (e) {
      setState(() {
        _testResult = '选择图片失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _takePicture() async {
    setState(() {
      _isLoading = true;
      _testResult = '正在启动相机...';
    });

    try {
      final path = await MediaService.takePicture();
      if (path != null) {
        setState(() {
          _selectedImagePath = path;
          _testResult =
              '成功拍照\n\n路径: ${path.length > 100 ? path.substring(0, 100) + '...' : path}\n\n'
              '图片格式: ${kIsWeb ? "Base64 (Web)" : "文件路径"}';
        });
      } else {
        setState(() {
          _testResult = '未拍照';
        });
      }
    } catch (e) {
      setState(() {
        _testResult = '拍照失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickVideo() async {
    setState(() {
      _isLoading = true;
      _testResult = '正在选择视频...';
    });

    try {
      final path = await MediaService.pickVideoFromGallery();
      if (path != null) {
        setState(() {
          _testResult = '成功选择视频\n\n路径: $path';
        });
      } else {
        setState(() {
          _testResult = '未选择视频';
        });
      }
    } catch (e) {
      setState(() {
        _testResult = '选择视频失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickFile() async {
    setState(() {
      _isLoading = true;
      _testResult = '正在选择文件...';
    });

    try {
      final result = await MediaService.pickFile();
      if (result != null && result.files.isNotEmpty) {
        final file = result.files;
        setState(() {
          _testResult =
              '成功选择文件\n\n'
              '文件名: ${file.map((f) => f.name).join(', ')}\n'
              '大小: ${file.map((f) => f.size).join(' bytes, ')}';
        });
      } else {
        setState(() {
          _testResult = '未选择文件';
        });
      }
    } catch (e) {
      setState(() {
        _testResult = '选择文件失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _startRecording() async {
    setState(() {
      _testResult = '正在请求麦克风权限...';
    });

    final hasPermission = await _audioService.checkPermission();
    if (!hasPermission) {
      setState(() {
        _testResult = '麦克风权限被拒绝';
      });
      return;
    }

    setState(() {
      _testResult = '正在开始录音...';
    });

    final success = await _audioService.startRecording();
    if (success && mounted) {
      setState(() {
        _isAudioRecording = true;
        _recordingDuration = 0;
        _testResult = '录音中...';
      });
      // 更新录音时长
      _updateRecordingDuration();
    } else {
      setState(() {
        _testResult = '开始录音失败';
      });
    }
  }

  void _updateRecordingDuration() {
    if (!_isAudioRecording) return;

    Future.delayed(const Duration(seconds: 1), () {
      if (_isAudioRecording && mounted) {
        setState(() {
          _recordingDuration = _audioService.getDurationInSeconds();
        });
        _updateRecordingDuration();
      }
    });
  }

  Future<void> _stopRecording() async {
    final path = await _audioService.stopRecording();
    setState(() {
      _isAudioRecording = false;
      _recordedAudioPath = path;
      _testResult = path != null
          ? '录音完成!\n\n路径: $path\n时长: $_recordingDuration 秒'
          : '录音失败';
    });
  }

  Future<void> _checkAudioPermission() async {
    setState(() {
      _testResult = '正在检查麦克风权限...';
    });

    final hasPermission = await _audioService.checkPermission();
    setState(() {
      _testResult = hasPermission ? '麦克风权限: 已授权' : '麦克风权限: 未授权';
    });
  }

  Future<void> _playAudio(String path) async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        if (kIsWeb) {
          await _audioPlayer.play(UrlSource(path));
        } else {
          await _audioPlayer.play(DeviceFileSource(path));
        }
      }
    } catch (e) {
      debugPrint('播放音频失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('原生媒体测试'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkCapabilities,
            tooltip: '重新检测',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 平台信息
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('运行环境', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('平台: ${kIsWeb ? 'Web' : 'Native'}'),
                    if (kIsWeb) Text('浏览器: ${defaultTargetPlatform}'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 功能检测
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('功能检测', style: theme.textTheme.titleMedium),
                        if (_isLoading)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_capability != null) ...[
                      _buildCapabilityItem(
                        '摄像头访问',
                        _capability!.canAccessCamera,
                      ),
                      _buildCapabilityItem(
                        '图库访问',
                        _capability!.canAccessGallery,
                      ),
                      _buildCapabilityItem('视频录制', _capability!.canRecordVideo),
                      const SizedBox(height: 8),
                      Text(
                        '支持的图片格式: ${_capability!.supportedImageFormats.join(', ')}',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        '支持的视频格式: ${_capability!.supportedVideoFormats.join(', ')}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ] else if (!_isLoading) ...[
                      const Text('点击右上角刷新按钮检测功能'),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 测试按钮
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('功能测试', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickFromGallery,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('从图库选择图片'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _takePicture,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('拍照'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickVideo,
                      icon: const Icon(Icons.videocam),
                      label: const Text('选择视频'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickFile,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('选择文件'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 录音测试
                    Text('录音功能测试', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isAudioRecording
                                ? null
                                : _startRecording,
                            icon: const Icon(Icons.mic),
                            label: const Text('开始录音'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isAudioRecording
                                ? _stopRecording
                                : null,
                            icon: const Icon(Icons.stop),
                            label: const Text('停止录音'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_isAudioRecording) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.fiber_manual_record,
                            color: Colors.red,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text('录音中: $_recordingDuration 秒'),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _checkAudioPermission,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('检查麦克风权限'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 测试结果
            if (_testResult.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('测试结果', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(_testResult),
                    ],
                  ),
                ),
              ),

            // 录音预览
            if (_recordedAudioPath != null && _recordedAudioPath!.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('录音预览', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                _isPlaying
                                    ? Icons.pause_circle
                                    : Icons.play_circle,
                              ),
                              iconSize: 40,
                              color: theme.colorScheme.primary,
                              onPressed: () => _playAudio(_recordedAudioPath!),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '录音文件',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  Text(
                                    '时长: $_recordingDuration 秒',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 图片预览
            if (_selectedImagePath.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('图片预览', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _selectedImagePath.startsWith('data:')
                            ? Image.network(
                                _selectedImagePath,
                                width: double.infinity,
                                height: 200,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    height: 200,
                                    color: Colors.grey[300],
                                    child: const Center(child: Text('图片加载失败')),
                                  );
                                },
                              )
                            : kIsWeb
                            ? Image.network(
                                _selectedImagePath,
                                width: double.infinity,
                                height: 200,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    height: 200,
                                    color: Colors.grey[300],
                                    child: const Center(child: Text('图片加载失败')),
                                  );
                                },
                              )
                            : Image.file(
                                File(_selectedImagePath),
                                width: double.infinity,
                                height: 200,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    height: 200,
                                    color: Colors.grey[300],
                                    child: Center(
                                      child: Text(
                                        '图片加载失败: $_selectedImagePath',
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapabilityItem(String label, bool value) {
    return Row(
      children: [
        Icon(
          value ? Icons.check_circle : Icons.cancel,
          color: value ? Colors.green : Colors.red,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}
