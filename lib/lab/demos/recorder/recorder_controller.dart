import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'const_recorder.dart';

/// 录音文件元数据 —— 列表页(Read)用。
class RecordingFile {
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime lastModified;

  const RecordingFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.lastModified,
  });

  double get sizeKb => sizeBytes / 1024;
}

/// RecorderController —— 录音状态机 + 文件落盘
///
/// 职责边界:
///   - 状态机:`RecorderState` 四态迁移 (idle → recording ↔ paused → stopped)
///   - 权限管理:封装 `permission_handler` 调用,UI 只读 [permissionStatus]
///   - 文件系统:录音文件统一放到 app documents/recordings/rec_xxx.aac
///   - 时长 ticker:`Timer.periodic(1s)` 仅用于 UI 显示,不写盘(避免 1Hz SP 抖动)
///
/// 设计约束:
///   - 单次录音只生成一个 [currentFilePath],重复 start 前必须 stop+discard
///   - [dispose] 时若仍在录音 → 自动 stop & 不保留(避免泄漏临时文件)
///   - 所有异常用 [errorNotifier] 通知 UI,不抛异常(UI 渲染时更友好)
class RecorderController extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();

  Timer? _ticker;

  RecorderState _state = RecorderState.idle;
  RecorderState get state => _state;

  Duration _elapsed = Duration.zero;
  Duration get elapsed => _elapsed;

  /// 当前录音文件绝对路径(idle / 完成后才有值;recording 时是空字符串占位)。
  String? _currentFilePath;
  String? get currentFilePath => _currentFilePath;

  /// 上一次完整录音的文件(stop 后赋值,UI save/discard 用)。
  String? _lastSavedPath;
  String? get lastSavedPath => _lastSavedPath;

  /// 最近一次保存/放弃后的文件大小(字节,UI 显示用)。
  int _lastFileSize = 0;
  int get lastFileSize => _lastFileSize;

  RecorderPermissionStatus _permissionStatus =
      RecorderPermissionStatus.unknown;
  RecorderPermissionStatus get permissionStatus => _permissionStatus;

  /// 错误事件 sink —— UI 用 `errorNotifier.addListener((){...showSnackBar...})`
  final ValueNotifier<String?> errorNotifier = ValueNotifier(null);

  /// 播放器(列表页试听)。null 表示从未初始化。
  final AudioPlayer _player = AudioPlayer();

  /// 当前播放的文件路径(无则 null)。
  String? _playingPath;
  String? get playingPath => _playingPath;

  bool _disposed = false;

  // ─────────────────────────── 权限 ───────────────────────────

  /// 请求麦克风权限并更新 [_permissionStatus]。
  /// 返回 true = 已授权。
  Future<bool> ensurePermission() async {
    final status = await Permission.microphone.request();
    _permissionStatus = _map(status);
    notifyListeners();
    return _permissionStatus == RecorderPermissionStatus.granted;
  }

  /// 仅查询,不弹系统弹窗(冷启动 widget 进入页时用)。
  Future<void> probePermission() async {
    final status = await Permission.microphone.status;
    _permissionStatus = _map(status);
    notifyListeners();
  }

  RecorderPermissionStatus _map(PermissionStatus s) {
    return switch (s) {
      PermissionStatus.granted || PermissionStatus.limited =>
        RecorderPermissionStatus.granted,
      PermissionStatus.denied => RecorderPermissionStatus.denied,
      PermissionStatus.permanentlyDenied ||
      PermissionStatus.restricted ||
      PermissionStatus.provisional =>
        RecorderPermissionStatus.permanentlyDenied,
      _ => RecorderPermissionStatus.unknown,
    };
  }

  // ─────────────────────────── 控制 ───────────────────────────

  /// 开始录音。内部生成 [fileName] 并写入 [currentFilePath]。
  ///
  /// 若已在 recording / paused → 返回 false(由 UI 提示)。
  /// 若未授权 → 自动 request,然后判断是否真正 granted。
  Future<bool> start() async {
    if (_state == RecorderState.recording ||
        _state == RecorderState.paused) {
      return false;
    }
    if (_permissionStatus != RecorderPermissionStatus.granted) {
      final ok = await ensurePermission();
      if (!ok) return false;
    }
    try {
      final dir = await _recordingsDir();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final filename = '${RecorderConsts.filePrefix}$ts.${RecorderConsts.fileExt}';
      final path = '${dir.path}${Platform.pathSeparator}$filename';

      // record 6.x:直接用 AudioEncoder enum,不再需要 EncoderConfig 工厂。
      final config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: RecorderDefaults.bitRate,
        sampleRate: RecorderDefaults.sampleRate,
        numChannels: RecorderDefaults.numChannels,
      );

      await _recorder.start(config, path: path);
      _currentFilePath = path;
      _elapsed = Duration.zero;
      _state = RecorderState.recording;
      _startTicker();
      _safeNotify();
      return true;
    } catch (e) {
      _emitError('开始录音失败: $e');
      return false;
    }
  }

  /// 暂停(若正在录音)。record 插件 5.x 开始支持 pause/resume。
  Future<void> pause() async {
    if (_state != RecorderState.recording) return;
    try {
      await _recorder.pause();
      _state = RecorderState.paused;
      _stopTicker();
      _safeNotify();
    } catch (e) {
      _emitError('暂停失败: $e');
    }
  }

  /// 继续(若已暂停)。
  Future<void> resume() async {
    if (_state != RecorderState.paused) return;
    try {
      await _recorder.resume();
      _state = RecorderState.recording;
      _startTicker();
      _safeNotify();
    } catch (e) {
      _emitError('继续录音失败: $e');
    }
  }

  /// 停止录音(不删除文件)。
  /// 返回最终文件路径(stopped 后调用方可决定 save or discard)。
  Future<String?> stop() async {
    if (_state != RecorderState.recording &&
        _state != RecorderState.paused) {
      return _currentFilePath;
    }
    try {
      final returnedPath = await _recorder.stop();
      _stopTicker();
      _state = RecorderState.stopped;
      // record 插件返回的 path 可能为 null(某些 codec),回落用我们写入的。
      _lastSavedPath = returnedPath ?? _currentFilePath;
      if (_lastSavedPath != null) {
        final f = File(_lastSavedPath!);
        if (await f.exists()) {
          _lastFileSize = await f.length();
        }
      }
      _safeNotify();
      return _lastSavedPath;
    } catch (e) {
      _emitError('停止录音失败: $e');
      return null;
    }
  }

  /// 放弃录音(stop 后调用),删除文件,回到 idle。
  Future<void> discard() async {
    final p = _lastSavedPath;
    _lastSavedPath = null;
    _lastFileSize = 0;
    _elapsed = Duration.zero;
    _state = RecorderState.idle;
    _safeNotify();
    if (p == null) return;
    try {
      final f = File(p);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 文件删除失败不阻塞 UI(临时文件,系统回收即可)
    }
  }

  /// 用户保存录音(目前 v1 仅暴露 lastSavedPath,不另存到 MediaStore)。
  /// 返回最终保存的文件路径(供 UI 弹 SnackBar)。
  String? commitSave() {
    final p = _lastSavedPath;
    _lastSavedPath = null;
    _lastFileSize = 0;
    _elapsed = Duration.zero;
    _state = RecorderState.idle;
    _safeNotify();
    return p;
  }

  // ─────────────────────────── 列表 / CRUD ───────────────────────────

  /// 读取 recordings/ 目录下所有 `.aac` 文件,按修改时间倒序。
  Future<List<RecordingFile>> listRecordings() async {
    try {
      final dir = await _recordingsDir();
      if (!await dir.exists()) return [];
      final files = await dir.list().where((e) {
        return e is File &&
            e.path.endsWith('.${RecorderConsts.fileExt}');
      }).toList();

      final result = <RecordingFile>[];
      for (final e in files) {
        final f = e as File;
        final stat = await f.stat();
        result.add(RecordingFile(
          path: f.path,
          name: f.path.split(Platform.pathSeparator).last,
          sizeBytes: stat.size,
          lastModified: stat.modified,
        ));
      }
      result.sort((a, b) => b.lastModified.compareTo(a.lastModified));
      return result;
    } catch (e) {
      _emitError('读取录音列表失败: $e');
      return [];
    }
  }

  /// 重命名录音文件。[newName] 不含扩展名(自动补 `.aac`)。
  /// 返回 null = 成功;返回 String = 错误提示。
  Future<String?> renameRecording(String oldPath, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return RecorderUiText.nameEmpty;

    final oldFile = File(oldPath);
    if (!await oldFile.exists()) return '文件不存在';
    final dir = oldFile.parent;
    final newPath =
        '${dir.path}${Platform.pathSeparator}$trimmed.${RecorderConsts.fileExt}';
    if (newPath != oldPath && await File(newPath).exists()) {
      return RecorderUiText.nameExists;
    }
    try {
      await oldFile.rename(newPath);
      if (_lastSavedPath == oldPath) _lastSavedPath = newPath;
      return null;
    } catch (e) {
      return '重命名失败: $e';
    }
  }

  /// 删除录音文件。若正在播放该文件先停止。返回是否成功。
  Future<bool> deleteRecording(String path) async {
    if (_playingPath == path) await _stopPlayback();
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
      if (_lastSavedPath == path) _lastSavedPath = null;
      return true;
    } catch (e) {
      _emitError('删除失败: $e');
      return false;
    }
  }

  /// 播放某条录音;若已是同一文件则切换播放/停止。
  Future<void> playFile(String path) async {
    if (_playingPath == path && _player.playing) {
      await _stopPlayback();
      return;
    }
    await _stopPlayback();
    try {
      await _player.setFilePath(path);
      _playingPath = path;
      _player.play();
      _safeNotify();
    } catch (e) {
      _emitError('播放失败: $e');
    }
  }

  Future<void> _stopPlayback() async {
    try {
      await _player.stop();
    } catch (_) {}
    _playingPath = null;
    _safeNotify();
  }

  /// 列表页离开时调用,停止播放释放资源。
  Future<void> stopPlayback() => _stopPlayback();

  // ─────────────────────────── ticker ───────────────────────────

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state != RecorderState.recording) return;
      _elapsed += const Duration(seconds: 1);
      // ticker 不调用 notifyListeners —— UI 用 AnimatedBuilder 订阅
      // errorNotifier/状态变化驱动重 build;时长由 _tickNotifier 暴露。
      _tickNotifier.value = _elapsed;
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// 时长 1Hz tick —— 只订阅这个 notifier 的 widget 每秒 build 一次,
  /// 其他 widget 不重建(性能隔离)。
  final ValueNotifier<Duration> _tickNotifier = ValueNotifier(Duration.zero);
  ValueListenable<Duration> get tickListenable => _tickNotifier;

  // ─────────────────────────── utils ───────────────────────────

  Future<Directory> _recordingsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${docs.path}${Platform.pathSeparator}${RecorderConsts.dirName}',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  void _emitError(String msg) {
    if (_disposed) return;
    errorNotifier.value = msg;
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTicker();
    // 若 dispose 时还在录音 → 静默 stop & 不保留(防止临时文件泄漏)。
    if (_state == RecorderState.recording ||
        _state == RecorderState.paused) {
      _recorder.stop().catchError((_) => null);
    }
    _recorder.dispose();
    _player.dispose();
    errorNotifier.dispose();
    _tickNotifier.dispose();
    super.dispose();
  }
}