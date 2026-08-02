/// 录音机模块常量 — 全部以 RecorderConsts.* 暴露，禁止散落硬编码。
///
/// 命名规范遵循项目 `flutter-work-flow` 规范:
/// `const_xxxx.dart` 统一管理一个模块的常量,减少跨文件维护成本。
library;

/// 文件名前缀 / 目录命名约定(用于显示 / 排序 / 防止中文文件名乱码)。
class RecorderConsts {
  RecorderConsts._();

  /// 文件名前缀,展示给用户看时去掉前缀。
  static const String filePrefix = 'rec_';

  /// 文件扩展名(aac 是 record 默认输出,体积小)。
  static const String fileExt = 'aac';

  /// 应用沙盒内录音文件目录(relative to getApplicationDocumentsDirectory).
  static const String dirName = 'recordings';

  /// 时长格式化阈值: < 1h 显示 mm:ss, >= 1h 显示 hh:mm:ss。
  static const int oneHourSeconds = 3600;
}

/// 录音状态枚举 — 单一可信状态源,Widget 只读。
enum RecorderState { idle, recording, paused, stopped }

/// 录音控件可读权限来源(供 widget autostart / UI 提示复用)。
enum RecorderPermissionStatus { granted, denied, permanentlyDenied, unknown }

/// 默认 codec/quality —— record 插件支持 AAC / OPUS,选 AAC 因为兼容性最广。
class RecorderDefaults {
  RecorderDefaults._();

  /// record 插件 Encoder.aacLc 是大多数 Android 设备原生支持的格式。
  static const String encoder = 'aacLc';

  /// 采样率 44100Hz = CD 音质;record 插件默认 44100,显式写出避免依赖默认值。
  static const int sampleRate = 44100;

  /// 比特率 128kbps,语音/会议够用,文件不大。
  static const int bitRate = 128000;

  /// 声道数 1(mono)—— 语音录音不需要立体声,文件减半。
  static const int numChannels = 1;
}

/// UI 控件名(label),便于 i18n / 测试时复用。
class RecorderUiText {
  RecorderUiText._();

  static const String start = '开始录音';
  static const String stop = '停止';
  static const String pause = '暂停';
  static const String resume = '继续';
  static const String save = '保存';
  static const String discard = '放弃';
  static const String savedPrefix = '已保存: ';
  static const String requestPermission = '请授予麦克风权限';
  static const String permissionDeniedHint =
      '录音权限被拒绝,可在系统设置 → 应用 → 小豆子 中开启';
  static const String noRecordingHint = '轻点下方按钮开始录音';
}