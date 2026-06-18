import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// block_editor_demo 的 AI 配置（独立于 ai_chat_provider）。
class AiSettings {
  final String apiKey;
  final String model;
  final String baseUrl;

  const AiSettings({
    this.apiKey = '',
    this.model = '',
    this.baseUrl = '',
  });

  bool get isConfigured => apiKey.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'model': model,
        'baseUrl': baseUrl,
      };

  factory AiSettings.fromJson(Map<String, dynamic> json) => AiSettings(
        apiKey: json['apiKey'] as String? ?? '',
        model: json['model'] as String? ?? '',
        baseUrl: json['baseUrl'] as String? ?? '',
      );
}

/// 用 SharedPreferences 持久化 [AiSettings]。
///
/// [prefsKey] 可注入，便于测试用独立 key 隔离。
class AiSettingsStore {
  final String prefsKey;
  AiSettingsStore({this.prefsKey = 'block_editor_ai_settings'});

  Future<AiSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return const AiSettings();
    try {
      return AiSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AiSettings();
    }
  }

  Future<void> save(AiSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode(settings.toJson()));
  }
}
