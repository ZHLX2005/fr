import 'package:shared_preferences/shared_preferences.dart';

import '../../../api/pi/pi.dart';

/// pi 聊天模块的轻量配置 —— SharedPreferences 存储。
///
/// 配置**完全可在 App 内设置**（对齐 `ai_chat_settings_page.dart` 的做法）；
/// 这里是唯一读写点，UI 与 Provider 都经由它。
class PiChatSettings {
  static const _kBaseUrl = 'pi_chat.baseUrl';
  static const _kToken = 'pi_chat.token';
  static const _kCwd = 'pi_chat.cwd';
  static const _kChannelPrefix = 'pi_chat.channelPrefix';
  static const _kDefaultModel = 'pi_chat.defaultModel';
  static const _kLastSessionId = 'pi_chat.lastSessionId';

  final SharedPreferences _prefs;

  PiChatSettings(this._prefs);

  // ── 读 ──────────────────────────────────────────

  String get baseUrl => _prefs.getString(_kBaseUrl) ?? '';

  String get token => _prefs.getString(_kToken) ?? '';

  /// 服务端会话工作目录（容器内路径）。默认 /data（线上容器数据卷）。
  String get cwd => _prefs.getString(_kCwd) ?? '/data';

  /// 手机通道前缀。默认线上 nginx 模式。
  String get channelPrefix =>
      _prefs.getString(_kChannelPrefix) ?? kPiNginxPrefix;

  /// 默认模型（`provider/modelId`）。空 = 跟随服务端默认。
  String get defaultModel => _prefs.getString(_kDefaultModel) ?? '';

  /// 上次使用的会话 id —— 冷启恢复用（否则每次进 pi 都是全新会话，
  /// 之前的对话在 UI 上就再也找不回来）。
  String get lastSessionId => _prefs.getString(_kLastSessionId) ?? '';

  bool get isConfigured => baseUrl.isNotEmpty && token.isNotEmpty;

  /// 组装成 API 层的 [PiConfig]（未配置时 token/baseUrl 为空串）。
  PiConfig toApiConfig() => PiConfig(
        baseUrl: baseUrl,
        token: token,
        cwd: cwd,
        channelPrefix: channelPrefix,
      );

  // ── 写 ──────────────────────────────────────────

  Future<void> setBaseUrl(String v) => _prefs.setString(_kBaseUrl, v.trim());

  Future<void> setToken(String v) => _prefs.setString(_kToken, v.trim());

  Future<void> setCwd(String v) =>
      _prefs.setString(_kCwd, v.trim().isEmpty ? '/data' : v.trim());

  Future<void> setChannelPrefix(String v) =>
      _prefs.setString(_kChannelPrefix, v.trim().isEmpty
          ? kPiNginxPrefix
          : v.trim());

  Future<void> setDefaultModel(String v) =>
      _prefs.setString(_kDefaultModel, v.trim());

  /// 记住当前会话（冷启恢复用）。
  Future<void> setLastSessionId(String v) =>
      _prefs.setString(_kLastSessionId, v.trim());

  /// 全量覆盖（设置页保存按钮的语义）。
  Future<void> saveAll({
    required String baseUrl,
    required String token,
    required String cwd,
    required String channelPrefix,
    required String defaultModel,
  }) async {
    await setBaseUrl(baseUrl);
    await setToken(token);
    await setCwd(cwd);
    await setChannelPrefix(channelPrefix);
    await setDefaultModel(defaultModel);
  }

  /// 清空全部配置（含 token）。
  Future<void> clear() async {
    await _prefs.remove(_kBaseUrl);
    await _prefs.remove(_kToken);
    await _prefs.remove(_kCwd);
    await _prefs.remove(_kChannelPrefix);
    await _prefs.remove(_kDefaultModel);
    await _prefs.remove(_kLastSessionId);
  }
}
