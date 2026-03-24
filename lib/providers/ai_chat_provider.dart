import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_chat_message.dart';
import '../services/api_client.dart';

/// AI Chat Provider - 管理 AI 聊天的状态和本地存储
class AIChatProvider with ChangeNotifier {
  static const String _messagesKey = 'ai_chat_messages';
  static const String _settingsKey = 'ai_chat_settings';

  List<AIChatMessage> _messages = [];
  AISettings _settings = AISettings();
  bool _isLoading = false;
  bool _isLoadingSettings = true; // 设置加载状态
  String? _error;

  List<AIChatMessage> get messages => _messages;
  AISettings get settings => _settings;
  bool get isLoading => _isLoading;
  bool get isLoadingSettings => _isLoadingSettings; // 新增
  String? get error => _error;
  bool get isConfigured => _settings.isConfigured;

  AIChatProvider() {
    _loadMessages();
    _loadSettings();
  }

  // 加载保存的消息
  Future<void> _loadMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_messagesKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        _messages = AIChatMessage.decodeList(jsonString);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('加载 AI 聊天消息失败: $e');
    }
  }

  // 保存消息到本地
  Future<void> _saveMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_messagesKey, AIChatMessage.encodeList(_messages));
    } catch (e) {
      debugPrint('保存 AI 聊天消息失败: $e');
    }
  }

  // 加载设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_settingsKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        _settings = AISettings.decode(jsonString);
      }
    } catch (e) {
      debugPrint('加载 AI 设置失败: $e');
    } finally {
      _isLoadingSettings = false;
      notifyListeners();
    }
  }

  // 保存设置
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_settingsKey, AISettings.encode(_settings));
    } catch (e) {
      debugPrint('保存 AI 设置失败: $e');
    }
  }

  // 更新设置
  Future<void> updateSettings(AISettings newSettings) async {
    _settings = newSettings;
    await _saveSettings();
    notifyListeners();
  }

  // 发送消息并获取 AI 响应
  Future<void> sendMessage(String content) async {
    if (!_settings.isConfigured) {
      _error = '请先配置 API Key';
      notifyListeners();
      return;
    }

    // 添加用户消息
    final userMessage = AIChatMessage.user(content);
    _messages.add(userMessage);

    // 添加 loading 消息
    final loadingMessage = AIChatMessage.loading();
    _messages.add(loadingMessage);

    _isLoading = true;
    _error = null;
    notifyListeners();

    await _saveMessages();

    try {
      // 调用后端 API
      final response = await _callAIChatAPI(content);

      // 移除 loading 消息
      _messages.remove(loadingMessage);

      if (response != null) {
        // 添加 AI 响应消息
        final assistantMessage = AIChatMessage.assistant(response);
        _messages.add(assistantMessage);
      } else {
        // 添加错误消息
        final errorMessage = AIChatMessage.assistant('抱歉，请求失败，请检查 API Key 或网络设置');
        _messages.add(errorMessage);
      }
    } catch (e) {
      // 移除 loading 消息
      _messages.remove(loadingMessage);

      final errorMessage = AIChatMessage.assistant('请求出错: $e');
      _messages.add(errorMessage);
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
    await _saveMessages();
  }

  // 调用后端 AI Chat API
  Future<String?> _callAIChatAPI(String prompt) async {
    try {
      final url = Uri.parse('${ApiService.baseUrl}/api/v1/ai/chat');

      final body = {
        'apiKey': _settings.apiKey,
        'prompt': prompt,
        if (_settings.model.isNotEmpty) 'model': _settings.model,
        if (_settings.baseURL.isNotEmpty) 'baseURL': _settings.baseURL,
        'type': _settings.type,
      };

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 180));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['data'] != null) {
          return json['data']['content'] as String?;
        }
      }

      debugPrint('AI Chat API 响应: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      debugPrint('AI Chat API 调用失败: $e');
      return null;
    }
  }

  // 清空聊天记录
  Future<void> clearMessages() async {
    _messages.clear();
    await _saveMessages();
    notifyListeners();
  }

  // 删除单条消息
  Future<void> deleteMessage(String id) async {
    _messages.removeWhere((m) => m.id == id);
    await _saveMessages();
    notifyListeners();
  }
}
