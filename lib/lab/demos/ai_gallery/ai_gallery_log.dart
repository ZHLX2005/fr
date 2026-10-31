import 'package:flutter/foundation.dart';

/// AI 图库运行期日志级别。
enum AiGalleryLogLevel { debug, info, warn, error }

extension AiGalleryLogLevelX on AiGalleryLogLevel {
  /// 列表里的短标签（等宽，宽度稳定）。
  String get label => switch (this) {
    AiGalleryLogLevel.debug => 'DBG',
    AiGalleryLogLevel.info => 'INF',
    AiGalleryLogLevel.warn => 'WRN',
    AiGalleryLogLevel.error => 'ERR',
  };
}

/// 一条运行期日志。
@immutable
class AiGalleryLogEntry {
  /// 自增序号（同一毫秒内的多条日志也能稳定排序）。
  final int seq;
  final DateTime time;
  final AiGalleryLogLevel level;

  /// 分类标签：`相册` / `AI请求` / `AI响应` / `解析失败` / `重试` …
  final String tag;

  /// 已按配置长度截断后的正文。
  final String message;

  /// 正文是否被截断（UI 上标注，避免误以为日志本身就不完整）。
  final bool truncated;

  const AiGalleryLogEntry({
    required this.seq,
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
    this.truncated = false,
  });

  String get formattedTime =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';
}

/// AI 图库的调试日志缓冲（内存单例）。
///
/// 设计意图：这个 demo 的失败几乎都来自「模型不听话」或「供应商报错」，
/// 靠手点看不出原因 —— 打开日志模式后，每条请求的提示词、原始回复、
/// 解析器错误、重试后的新提示词全部留痕，直接在设置页里翻看。
///
/// 长度完全由配置决定（[maxEntries] 条数上限、[maxChars] 单条字数上限），
/// 默认关闭：关着的时候 [add] 连字符串都不拼，release 包零成本。
class AiGalleryLog extends ChangeNotifier {
  AiGalleryLog._();

  static final AiGalleryLog instance = AiGalleryLog._();

  /// 硬上限，防止设置页误配把内存撑爆。
  static const int entriesFloor = 20;
  static const int entriesCeil = 2000;
  static const int charsFloor = 80;
  static const int charsCeil = 20000;

  bool _enabled = false;
  int _maxEntries = 300;
  int _maxChars = 1500;
  final List<AiGalleryLogEntry> _entries = <AiGalleryLogEntry>[];
  int _seq = 0;

  bool get enabled => _enabled;
  int get maxEntries => _maxEntries;
  int get maxChars => _maxChars;

  /// 只读快照（时间正序：旧 → 新）。
  List<AiGalleryLogEntry> get entries => List.unmodifiable(_entries);

  int get errorCount =>
      _entries.where((e) => e.level == AiGalleryLogLevel.error).length;

  /// 从设置页写入。关掉时不清空已有日志 —— 用户可能只是暂时关掉
  /// 记录，之前抓到的现场还要留给他看。
  void configure({bool? enabled, int? maxEntries, int? maxChars}) {
    _enabled = enabled ?? _enabled;
    _maxEntries = (maxEntries ?? _maxEntries).clamp(entriesFloor, entriesCeil);
    _maxChars = (maxChars ?? _maxChars).clamp(charsFloor, charsCeil);
    _trim();
    notifyListeners();
  }

  void add(AiGalleryLogLevel level, String tag, String message) {
    if (!_enabled) return;
    final full = message.trim();
    final truncated = full.length > _maxChars;
    final text = truncated ? '${full.substring(0, _maxChars)}…' : full;
    _entries.add(
      AiGalleryLogEntry(
        seq: ++_seq,
        time: DateTime.now(),
        level: level,
        tag: tag,
        message: text,
        truncated: truncated,
      ),
    );
    _trim();
    debugPrint('[AiGallery/${level.label}] $tag: $text');
    notifyListeners();
  }

  void debug(String tag, String message) =>
      add(AiGalleryLogLevel.debug, tag, message);
  void info(String tag, String message) =>
      add(AiGalleryLogLevel.info, tag, message);
  void warn(String tag, String message) =>
      add(AiGalleryLogLevel.warn, tag, message);
  void error(String tag, String message) =>
      add(AiGalleryLogLevel.error, tag, message);

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  /// 导出成可粘贴的纯文本（反馈问题 / 贴给模型看）。
  String exportText() {
    final b = StringBuffer()
      ..writeln('# AI 图库日志 · ${_entries.length} 条')
      ..writeln('# 单条上限 $_maxChars 字 · 条数上限 $_maxEntries');
    for (final e in _entries) {
      b.writeln(
        '[${e.formattedTime}][${e.level.label}][${e.tag}] '
        '${e.message}${e.truncated ? '（已截断）' : ''}',
      );
    }
    return b.toString();
  }

  void _trim() {
    final overflow = _entries.length - _maxEntries;
    if (overflow > 0) _entries.removeRange(0, overflow);
  }
}
