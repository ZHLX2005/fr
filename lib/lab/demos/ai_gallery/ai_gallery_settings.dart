import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../api/llm/llm.dart';
import 'ai_gallery_log.dart';

/// AI 图库配置。
///
/// 独立于 ai_chat 的 [AISettings]（那份耦合了 DB 配置且归 AI 中心聊天用）；
/// 本配置属于 ai-gallery demo 自己，存 SharedPreferences。
@immutable
class AiGallerySettings {
  /// `openai` / `anthropic`（[LlmEndpoint.protocols] 的 key）。
  final String protocolId;

  /// LLM 服务地址，如 `https://api.openai.com`（不含路径，协议负责拼路径）。
  final String baseUrl;

  /// API Key（明文本地存储；Lab demo 级别不引入加密存储）。
  final String apiKey;

  /// 模型名，如 `gpt-4o-mini` / `claude-sonnet-4-6`。
  final String model;

  /// 自定义扫描提示词（要求 AI 输出 JSON）。
  final String prompt;

  /// 自动扫描最新图片数量（X）。
  final int scanCount;

  /// 最大并发请求数（1 = 串行）。
  final int maxConcurrency;

  /// 进入页面自动开始扫描。
  final bool autoScan;

  /// 单张失败后的重试次数（不含首次请求）。0 = 不重试。
  ///
  /// 重试不是原样重发：解析失败时会把解析器的错误 + 上一次原始回复
  /// 拼进提示词再请求（见 `ai_gallery_prompt.dart`）。
  final int retryCount;

  /// 日志模式：默认关闭，开启后请求/响应/解析错误全部留痕。
  final bool logEnabled;

  /// 日志条数上限（超出后丢最旧的）。
  final int logMaxEntries;

  /// 单条日志字数上限（超出截断）。
  final int logMaxChars;

  const AiGallerySettings({
    this.protocolId = 'openai',
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.prompt = kDefaultGalleryPrompt,
    this.scanCount = 12,
    this.maxConcurrency = 1,
    this.autoScan = false,
    this.retryCount = 2,
    this.logEnabled = false,
    this.logMaxEntries = 300,
    this.logMaxChars = 1500,
  });

  bool get isConfigured => baseUrl.isNotEmpty && apiKey.isNotEmpty && model.isNotEmpty;

  /// 把日志相关配置同步到运行期日志缓冲（进入页面、改配置时调用）。
  void applyLogConfig() => AiGalleryLog.instance.configure(
    enabled: logEnabled,
    maxEntries: logMaxEntries,
    maxChars: logMaxChars,
  );

  AiGallerySettings copyWith({
    String? protocolId,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? prompt,
    int? scanCount,
    int? maxConcurrency,
    bool? autoScan,
    int? retryCount,
    bool? logEnabled,
    int? logMaxEntries,
    int? logMaxChars,
  }) {
    return AiGallerySettings(
      protocolId: protocolId ?? this.protocolId,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      prompt: prompt ?? this.prompt,
      scanCount: scanCount ?? this.scanCount,
      maxConcurrency: maxConcurrency ?? this.maxConcurrency,
      autoScan: autoScan ?? this.autoScan,
      retryCount: retryCount ?? this.retryCount,
      logEnabled: logEnabled ?? this.logEnabled,
      logMaxEntries: logMaxEntries ?? this.logMaxEntries,
      logMaxChars: logMaxChars ?? this.logMaxChars,
    );
  }

  Map<String, dynamic> toJson() => {
    'protocolId': protocolId,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'prompt': prompt,
    'scanCount': scanCount,
    'maxConcurrency': maxConcurrency,
    'autoScan': autoScan,
    'retryCount': retryCount,
    'logEnabled': logEnabled,
    'logMaxEntries': logMaxEntries,
    'logMaxChars': logMaxChars,
  };

  factory AiGallerySettings.fromJson(Map<String, dynamic> json) =>
      AiGallerySettings(
        protocolId: json['protocolId'] as String? ?? 'openai',
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
        model: json['model'] as String? ?? '',
        prompt: json['prompt'] as String? ?? kDefaultGalleryPrompt,
        scanCount: json['scanCount'] as int? ?? 12,
        maxConcurrency: json['maxConcurrency'] as int? ?? 1,
        autoScan: json['autoScan'] as bool? ?? false,
        retryCount: json['retryCount'] as int? ?? 2,
        logEnabled: json['logEnabled'] as bool? ?? false,
        logMaxEntries: json['logMaxEntries'] as int? ?? 300,
        logMaxChars: json['logMaxChars'] as int? ?? 1500,
      );

  static String encode(AiGallerySettings s) => jsonEncode(s.toJson());

  static AiGallerySettings decode(String raw) {
    try {
      return AiGallerySettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const AiGallerySettings();
    }
  }
}

/// 默认提示词 —— 明确要求 JSON、给定字段契约（详情页完全由返回 JSON 驱动）。
const String kDefaultGalleryPrompt = '''
你是相册分析助手。分析这张图片，只输出一个 JSON 对象（不要 markdown 代码块，不要解释文字），字段：
- "title": 简短标题（不超过 12 字）
- "description": 一句话描述（不超过 40 字）
- "group": 分组名，从这些里选一个最贴切的：截图、照片、文档、二维码、聊天记录、其他
- "tags": 标签数组（2-5 个字符串）
- "importance": 重要性，"high" / "medium" / "low"（AI 自行推断，high 的在列表中标注）
除上述字段外，若图片中还有值得结构化记录的信息（如二维码内容、文档要点、地点、人物、时间等），以额外字段加入 JSON。''';

/// AI 图库配置存取（SharedPreferences，key 隔离在 ai_gallery 前缀下）。
///
/// 注意：**保存动作要真的发生**。之前的 bug 就是设置页把结果 pop 回主页后
/// 没人写盘，退出去再进来 apiKey/模型全丢（看着像「密钥没持久化」）。
/// 现在设置页点保存时自己落盘，主页只负责接收返回值。
class AiGallerySettingsStore {
  static const _key = 'ai_gallery_settings_v1';

  Future<AiGallerySettings> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key) ?? '';
    final settings = AiGallerySettings.decode(raw);
    settings.applyLogConfig();
    return settings;
  }

  /// 写盘并返回是否成功（失败时日志里留痕，不静默吞）。
  Future<bool> save(AiGallerySettings s) async {
    final sp = await SharedPreferences.getInstance();
    final ok = await sp.setString(_key, AiGallerySettings.encode(s));
    if (!ok) {
      AiGalleryLog.instance.error('配置', '写入 SharedPreferences 失败');
    } else {
      AiGalleryLog.instance.info(
        '配置',
        '已保存 · ${s.protocolId} · ${s.model} · key ${s.apiKey.isEmpty ? '空' : '${s.apiKey.length} 位'}'
        ' · 重试 ${s.retryCount} · 日志 ${s.logEnabled ? '开' : '关'}',
      );
    }
    return ok;
  }

  Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }
}
