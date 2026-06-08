/// MiniMax TTS API 配置常量。
class MiniMaxConfig {
  /// WebSocket 端点（非标准 HTTP，独立走 ws://）。
  static const String wsUrl = 'wss://api.minimaxi.com/ws/v1/t2a_v2';

  /// 默认音色。
  static const String defaultVoiceId = 'female-yujie';

  /// 默认模型。
  static const String defaultModel = 'speech-2.8-hd';

  MiniMaxConfig._();
}
