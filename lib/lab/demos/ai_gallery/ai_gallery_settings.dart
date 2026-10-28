import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../api/llm/llm.dart';

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

  const AiGallerySettings({
    this.protocolId = 'openai',
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.prompt = kDefaultGalleryPrompt,
    this.scanCount = 12,
    this.maxConcurrency = 1,
    this.autoScan = false,
  });

  bool get isConfigured => baseUrl.isNotEmpty && apiKey.isNotEmpty && model.isNotEmpty;

  AiGallerySettings copyWith({
    String? protocolId,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? prompt,
    int? scanCount,
    int? maxConcurrency,
    bool? autoScan,
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
class AiGallerySettingsStore {
  static const _key = 'ai_gallery_settings_v1';

  Future<AiGallerySettings> load() async {
    final sp = await SharedPreferences.getInstance();
    return AiGallerySettings.decode(sp.getString(_key) ?? '');
  }

  Future<void> save(AiGallerySettings s) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, AiGallerySettings.encode(s));
  }
}
