import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ffi_bindings.dart';

/// Ships the built-in "woodfish" WAV from `assets/audio/woodfish.wav` down to
/// the app's private support directory and mounts it onto an accent-level slot
/// via [MetronomeFFI.loadSample]. Also provides a hook for third-party samples
/// (e.g. user-supplied WAV) — pass any asset key here and it will be copied
/// to disk and returned as a filesystem path.
///
/// Why we bother with a filesystem copy: the native `load_sample` uses
/// `fopen` inside dr_wav. Flutter assets are packed inside the APK and do
/// NOT have a real path — so we materialize a copy the first time we need
/// it, then cache the path forever.
class SampleLoader {
  SampleLoader._();

  /// Cached path -> already extracted (so we don't rewrite the file on every
  /// call). Keyed by asset key.
  static final Map<String, String> _extractedCache = {};

  /// Guard flag: default samples have been mounted for this process.
  static bool _defaultsMounted = false;

  /// Materialize an asset to the app's support dir. Returns the file path.
  /// Idempotent: subsequent calls hit the cache.
  static Future<String> materializeAsset(String assetKey) async {
    final cached = _extractedCache[assetKey];
    if (cached != null && await File(cached).exists()) return cached;

    final data = await rootBundle.load(assetKey);
    final dir = await getApplicationSupportDirectory();
    final outDir = Directory('${dir.path}/metronome_samples');
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    // File name = last segment of asset key (assets/audio/woodfish.wav -> woodfish.wav).
    final fileName = assetKey.split('/').last;
    final outPath = '${outDir.path}/$fileName';
    final file = File(outPath);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    _extractedCache[assetKey] = outPath;
    return outPath;
  }

  /// Preload the built-in woodfish tone into the *accent* slot (level 2).
  /// Runs once per process; subsequent calls are no-ops. Fire-and-forget from
  /// the audio init path — a failure here just means the app falls back to the
  /// synth click.
  static Future<void> mountDefaults() async {
    if (_defaultsMounted) return;
    _defaultsMounted = true; // mark up-front so we don't retry on error storm
    try {
      final path = await materializeAsset('assets/audio/woodfish.wav');
      MetronomeFFI.loadSample(2, path); // 2 == accent
    } catch (e) {
      // Swallow. The metronome still works — user just won't hear the sample.
      // Reset flag so a future manual retry (e.g. from a settings page) works.
      _defaultsMounted = false;
    }
  }

  /// Mount a user-provided sample from an arbitrary asset key onto the given
  /// accent level. Exposed for a future "custom tick" UI.
  static Future<bool> mountAssetTo(int level, String assetKey) async {
    try {
      final path = await materializeAsset(assetKey);
      return MetronomeFFI.loadSample(level, path);
    } catch (_) {
      return false;
    }
  }

  /// Mount a user-provided sample directly from an already-materialized file
  /// path (e.g. from file_picker). No asset materialization needed.
  static bool mountPathTo(int level, String absolutePath) {
    return MetronomeFFI.loadSample(level, absolutePath);
  }

  // ==================== 启动期声音还原（修 beat 冷启动默认声 bug, fr #2）====================

  /// 各 accent 槽的默认 soundId：weak=合成, medium=合成, accent=木鱼。
  /// 为何 accent 默认木鱼：clock 的 beat 强拍落在 accent 槽，冷启动直进
  /// clock→beat 必须有木鱼（fr #2），即使用户从没进过 metronome 配置。
  static const List<int> _slotDefaults = [0, 0, 1];

  /// 某槽的默认 soundId（0=合成, 1=木鱼）。
  static int slotDefault(int level) =>
      level >= 0 && level < _slotDefaults.length ? _slotDefaults[level] : 0;

  /// 结合用户 SharedPreferences 存值与默认，得到该槽应使用的 soundId。
  /// saved=null（没存过）→ 用默认；saved!=null → 尊重用户显式选择。
  static int resolveSoundId(int? saved, int level) =>
      saved ?? slotDefault(level);

  static const String _slotKeyPrefix = 'metronome_slot_';

  /// App 启动时调一次（幂等）。把用户在 metronome 页配过的声音槽还原到
  /// 共享 FFI 单例，等价于"自动进过一次 metronome"，冷启动直进 clock→beat
  /// 也能听到正确音色。accent 槽默认木鱼，无需用户配置。
  static Future<void> restoreAtStartup() async {
    if (_startupRestored) return;
    _startupRestored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (var level = 0; level < 3; level++) {
        final saved = prefs.getInt('$_slotKeyPrefix$level');
        final soundId = resolveSoundId(saved, level);
        if (soundId == 1) {
          final path = await materializeAsset('assets/audio/woodfish.wav');
          MetronomeFFI.loadSample(level, path);
        } else {
          MetronomeFFI.clearSample(level);
        }
      }
    } catch (_) {
      // 失败回退：允许下次重试（如进入 metronome 页时 _restoreSoundSlots）。
      _startupRestored = false;
    }
  }

  static bool _startupRestored = false;

  /// Test-only: reset the cache and mount flag so tests get a clean slate.
  static void resetForTest() {
    _extractedCache.clear();
    _defaultsMounted = false;
    _startupRestored = false;
  }
}
